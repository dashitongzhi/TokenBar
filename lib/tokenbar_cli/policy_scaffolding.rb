# frozen_string_literal: true

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
      lines = [
        "version: 1",
        "",
        "workspace:",
        "  id: #{yaml_scalar(options[:workspace_id])}",
        "  name: #{yaml_scalar(options[:workspace_name])}",
        "  path: #{yaml_scalar(options[:workspace_path])}",
        "  client: #{yaml_scalar(options[:client])}",
        "",
        "budgets:",
        "  daily: #{money(options[:daily_budget])}",
        "  monthly: #{money(options[:monthly_budget])}",
        "  max_run: #{money(options[:max_run])}",
        "  spend_today: #{money(options[:spend_today])}",
        "  spend_month: #{money(options[:spend_month])}",
        "",
        "rules:",
        "  max_estimated_tokens: #{options[:max_estimated_tokens]}",
        "",
        "providers:",
        "  allowed:",
        *options[:allowed_providers].map { |provider| "    - #{yaml_scalar(provider)}" },
        "  preferred: #{yaml_scalar(options[:preferred_provider])}",
        "  require_company_key: #{options[:require_company_key] ? "true" : "false"}",
        "",
        "models:"
      ]
      lines << "  default: #{yaml_scalar(options[:default_model])}"
      if options[:blocked_models].empty?
        lines << "  blocked: []"
      else
        lines << "  blocked:"
        lines.concat(options[:blocked_models].map { |model| "    - #{yaml_scalar(model)}" })
      end
      if options[:inference]
        inference = options[:inference]
        lines.concat([
          "",
          "setup:",
          "  source: #{yaml_scalar(inference[:source])}",
          "  configured_models: #{inference[:configured_models].to_i}",
          "  inferred_from:"
        ])
        paths = Array(inference[:paths])
        if paths.empty?
          lines << "    - #{yaml_scalar(options[:workspace_path])}"
        else
          lines.concat(paths.map { |path| "    - #{yaml_scalar(path)}" })
        end
      end
      lines << ""
      lines.join("\n")
    end

    def yaml_scalar(value)
      string = value.to_s
      return "\"\"" if string.empty?
      return string if string.match?(/\A[a-zA-Z0-9_.\/~:-]+\z/) && !%w[true false null yes no on off].include?(string.downcase)

      string.inspect
    end

    def money(value)
      format("%.2f", value)
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
                      "command" => "TOKENBAR_BIN=#{root.join("bin/tokenbar").to_s.inspect} #{root.join("examples/hooks/codex-tokenbar-user-prompt-submit.sh").to_s.inspect}",
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
                      "command" => "TOKENBAR_BIN=#{root.join("bin/tokenbar").to_s.inspect} #{root.join("examples/hooks/codex-tokenbar-stop.sh").to_s.inspect}",
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
              "command" => "TOKENBAR_BIN=#{root.join("bin/tokenbar").to_s.inspect} #{root.join("examples/hooks/claude-tokenbar-statusline.sh").to_s.inspect}",
              "padding" => 0
            },
            "hooks" => {
              "UserPromptSubmit" => [
                {
                  "hooks" => [
                    {
                      "type" => "command",
                      "command" => "TOKENBAR_BIN=#{root.join("bin/tokenbar").to_s.inspect} #{root.join("examples/hooks/claude-tokenbar-user-prompt-submit.sh").to_s.inspect}",
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
