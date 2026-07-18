# frozen_string_literal: true

module TokenBarCLI
  module Commands
    module Policy
      def policy(options, argv)
        subcommand = argv.shift
        raise Error, "missing policy command: use init" unless subcommand

        case subcommand
        when "init"
          policy_init(options, argv)
        else
          raise Error, "unknown policy command: #{subcommand}"
        end
      end

      def policy_init(options, argv)
        root = repo_root
        cwd = Pathname.pwd.expand_path
        inferred = infer_workspace_policy(cwd)
        init_options = {
          output: cwd.join("tokenbar.yml"),
          workspace_id: slug(cwd.basename.to_s),
          workspace_name: titleize(cwd.basename.to_s),
          workspace_path: cwd.to_s,
          client: "local",
          daily_budget: 8.00,
          monthly_budget: 160.00,
          max_run: inferred[:max_run],
          max_estimated_tokens: 0,
          spend_today: 0.00,
          spend_month: 0.00,
          allowed_providers: inferred[:allowed_providers],
          preferred_provider: inferred[:preferred_provider],
          default_model: inferred[:default_model],
          require_company_key: false,
          blocked_models: inferred[:blocked_models],
          inference: inferred,
          hooks: [],
          force: false
        }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: tokenbar policy init [--hooks codex,claude|all] [options]"
          opts.on("--output PATH", "Write policy YAML to PATH (default: ./tokenbar.yml)") { |value| init_options[:output] = Pathname.new(value).expand_path }
          opts.on("--workspace-id ID", "Workspace id (default: current directory slug)") { |value| init_options[:workspace_id] = value }
          opts.on("--workspace-name NAME", "Workspace display name (default: current directory name)") { |value| init_options[:workspace_name] = value }
          opts.on("--client CLIENT", "Client or owner label (default: local)") { |value| init_options[:client] = value }
          opts.on("--daily-budget USD", Float, "Daily budget in USD (default: 8.00)") { |value| init_options[:daily_budget] = value }
          opts.on("--monthly-budget USD", Float, "Monthly budget in USD (default: 160.00)") { |value| init_options[:monthly_budget] = value }
          opts.on("--max-run-cost USD", Float, "Per-run cost cap in USD; 0 disables the cap (default: inferred from local agent config)") { |value| init_options[:max_run] = value }
          opts.on("--max-estimated-tokens TOKENS", Integer, "Block a run above this estimated token count (0 disables the cap)") { |value| init_options[:max_estimated_tokens] = value }
          opts.on("--allowed-providers LIST", "Comma-separated providers (default: inferred from local agent config)") { |value| init_options[:allowed_providers] = split_list(value) }
          opts.on("--preferred-provider PROVIDER", "Preferred provider (default: inferred from local agent config)") { |value| init_options[:preferred_provider] = value }
          opts.on("--default-model MODEL", "Default model written to models.default (default: inferred from local agent config)") { |value| init_options[:default_model] = value }
          opts.on("--require-company-key", "Block OpenAI runs unless company-key policy is satisfied") { init_options[:require_company_key] = true }
          opts.on("--blocked-models LIST", "Comma-separated blocked model substrings (default: opus,gpt-5-pro)") { |value| init_options[:blocked_models] = split_list(value) }
          opts.on("--hooks LIST", "Write hook config for codex, claude, or all") { |value| init_options[:hooks] = parse_hooks(value) }
          opts.on("--codex-hooks", "Write .codex/hooks.json") { init_options[:hooks] |= ["codex"] }
          opts.on("--claude-hooks", "Write .claude/settings.local.json") { init_options[:hooks] |= ["claude"] }
          opts.on("--force", "Overwrite generated files if they already exist") { init_options[:force] = true }
          opts.on("--json", "Print machine-readable JSON") { options[:json] = true }
          opts.on("-h", "--help", "Show help") do
            puts opts
            exit 0
          end
        end
        parser.parse!(argv)

        validate_init_options!(init_options)
        targets = [[init_options[:output], policy_yaml(init_options)]]
        targets += init_options[:hooks].map { |hook| hook_file(hook, cwd, root) }
        preflight_writes!(targets.map(&:first), force: init_options[:force])
        targets.each { |path, body| write_file(path, body) }
        written = targets.map { |path, _body| path.to_s }

        config = load_config(init_options[:output].to_s)
        sample_input = {
          "agent" => "codex",
          "workspaceID" => init_options[:workspace_id],
          "providerID" => init_options[:preferred_provider],
          "model" => init_options[:default_model],
          "estimatedCost" => 0.0,
          "estimatedTokens" => 0,
          "intent" => "policy_init_smoke"
        }
        decision = offline_policy_response(sample_input, config).fetch("decision")

        payload = {
          "policy" => init_options[:output].to_s,
          "hooks" => init_options[:hooks],
          "written" => written,
          "inference" => inferred,
          "smokeDecision" => {
            "status" => decision["status"],
            "reasons" => decision["reasons"]
          }
        }

        if options[:json]
          puts JSON.pretty_generate(payload)
        else
          print_policy_init(payload)
        end
      end
    end
  end
end
