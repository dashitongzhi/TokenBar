# frozen_string_literal: true

require "shellwords"

module TokenBarCLI
  module PolicyScaffolding
    def validate_init_options!(options)
      raise Error, "--workspace-id cannot be empty" if blank?(options[:workspace_id])
      raise Error, "--workspace-name cannot be empty" if blank?(options[:workspace_name])
      raise Error, "--daily-budget must be >= 0" if options[:daily_budget].negative?
      raise Error, "--monthly-budget must be >= 0" if options[:monthly_budget].negative?
      raise Error, "--max-run-cost must be >= 0" if options[:max_run].negative?
      raise Error, "--max-estimated-tokens must be >= 0" if options[:max_estimated_tokens].negative?
      raise Error, "--allowed-providers cannot be empty" if options[:allowed_providers].empty?
      raise Error, "--default-model cannot be empty" if blank?(options[:default_model])
      unless options[:allowed_providers].include?(options[:preferred_provider])
        raise Error, "--preferred-provider must be included in --allowed-providers"
      end
    end

    def policy_yaml(options)
      document = {
        "version" => 1,
        "workspace" => {
          "id" => options[:workspace_id].to_s,
          "name" => options[:workspace_name].to_s,
          "path" => options[:workspace_path].to_s,
          "client" => options[:client].to_s
        },
        "budgets" => {
          "daily" => money_value(options[:daily_budget]),
          "monthly" => money_value(options[:monthly_budget]),
          "max_run" => money_value(options[:max_run]),
          "spend_today" => money_value(options[:spend_today]),
          "spend_month" => money_value(options[:spend_month])
        },
        "rules" => {
          "max_estimated_tokens" => options[:max_estimated_tokens].to_i
        },
        "providers" => {
          "allowed" => options[:allowed_providers].map(&:to_s),
          "preferred" => options[:preferred_provider].to_s,
          "require_company_key" => options[:require_company_key] == true
        },
        "models" => {
          "default" => options[:default_model].to_s,
          "blocked" => options[:blocked_models].map(&:to_s)
        }
      }
      if options[:inference]
        inference = options[:inference]
        paths = Array(inference[:paths])
        document["setup"] = {
          "source" => inference[:source].to_s,
          "configured_models" => inference[:configured_models].to_i,
          "inferred_from" => (paths.empty? ? [options[:workspace_path]] : paths).map(&:to_s)
        }
      end
      YAML.dump(document)
    end

    def money_value(value)
      format("%.2f", value).to_f
    end

    def hook_file(hook, cwd, root)
      case hook
      when "codex"
        [
          cwd.join(".codex/hooks.json"),
          JSON.pretty_generate(
            "hooks" => {
              "UserPromptSubmit" => [
                {
                  "hooks" => [
                    {
                      "type" => "command",
                      "command" => "TOKENBAR_BIN=#{Shellwords.escape(root.join("bin/tokenbar").to_s)} #{Shellwords.escape(root.join("examples/hooks/codex-tokenbar-user-prompt-submit.sh").to_s)}",
                      "timeout" => 10,
                      "statusMessage" => "Checking TokenBar policy"
                    }
                  ]
                }
              ],
              "Stop" => [
                {
                  "hooks" => [
                    {
                      "type" => "command",
                      "command" => "TOKENBAR_BIN=#{Shellwords.escape(root.join("bin/tokenbar").to_s)} #{Shellwords.escape(root.join("examples/hooks/codex-tokenbar-stop.sh").to_s)}",
                      "timeout" => 10,
                      "statusMessage" => "Sending Codex usage to TokenBar"
                    }
                  ]
                }
              ]
            }
          ) + "\n"
        ]
      when "claude"
        [
          cwd.join(".claude/settings.local.json"),
          JSON.pretty_generate(
            "statusLine" => {
              "type" => "command",
              "command" => "TOKENBAR_BIN=#{Shellwords.escape(root.join("bin/tokenbar").to_s)} #{Shellwords.escape(root.join("examples/hooks/claude-tokenbar-statusline.sh").to_s)}",
              "padding" => 0
            },
            "hooks" => {
              "UserPromptSubmit" => [
                {
                  "hooks" => [
                    {
                      "type" => "command",
                      "command" => "TOKENBAR_BIN=#{Shellwords.escape(root.join("bin/tokenbar").to_s)} #{Shellwords.escape(root.join("examples/hooks/claude-tokenbar-user-prompt-submit.sh").to_s)}",
                      "timeout" => 10
                    }
                  ]
                }
              ]
            }
          ) + "\n"
        ]
      else
        raise Error, "unsupported hook target: #{hook}"
      end
    end

    def preflight_writes!(paths, force:)
      return if force

      existing = paths.select(&:exist?)
      return if existing.empty?

      raise Error, "#{existing.first} already exists; pass --force to overwrite"
    end

    def write_file(path, body)
      FileUtils.mkdir_p(path.dirname)
      path.write(body)
    end
  end
end
