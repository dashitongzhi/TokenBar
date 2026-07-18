# frozen_string_literal: true

module TokenBarCLI
  module Commands
    module StatusCheck
      def status(options, argv)
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: tokenbar status [--json]"
          opts.on("--json", "Print machine-readable JSON") { options[:json] = true }
          opts.on("-h", "--help", "Show help") do
            puts opts
            exit 0
          end
        end
        parser.parse!(argv)

        config = load_config(options[:config_path])
        api = fetch_api_status(options[:api_url])
        payload = {
          "api" => api,
          "config" => config_summary(config),
          "source" => api["running"] ? "local_api" : "tokenbar_yml"
        }

        if options[:json]
          puts JSON.pretty_generate(payload)
        else
          print_status(payload)
        end

        exit(api["running"] || config ? 0 : 3)
      end

      def check(options, argv)
        input = {
          "agent" => ENV.fetch("TOKENBAR_AGENT", "custom"),
          "workspaceID" => nil,
          "providerID" => ENV["TOKENBAR_PROVIDER"],
          "model" => ENV["TOKENBAR_MODEL"],
          "estimatedCost" => numeric_env("TOKENBAR_ESTIMATED_COST", nil),
          "estimatedTokens" => integer_env("TOKENBAR_ESTIMATED_TOKENS", nil),
          "keySource" => ENV["TOKENBAR_KEY_SOURCE"],
          "intent" => ENV.fetch("TOKENBAR_INTENT", "unspecified")
        }
        check_options = {
          codex_hook_json: false,
          prompt: ENV["TOKENBAR_PROMPT"],
          prompt_file: ENV["TOKENBAR_PROMPT_FILE"],
          provider_explicit: !blank?(ENV["TOKENBAR_PROVIDER"]),
          cost_explicit: !blank?(ENV["TOKENBAR_ESTIMATED_COST"]),
          tokens_explicit: !blank?(ENV["TOKENBAR_ESTIMATED_TOKENS"])
        }
        output_json = options[:json]

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: tokenbar check --agent AGENT --provider PROVIDER --model MODEL [options]"
          opts.on("--agent AGENT", "claudeCode, codex, cursor, continueDev, or custom") { |value| input["agent"] = value }
          opts.on("--workspace-id ID", "Override tokenbar.yml workspace id") { |value| input["workspaceID"] = value }
          opts.on("--provider PROVIDER", "Provider id, such as anthropic or openai") { |value| input["providerID"] = value; check_options[:provider_explicit] = true }
          opts.on("--model MODEL", "Model name or slug") { |value| input["model"] = value }
          opts.on("--estimated-cost COST", Float, "Estimated run cost in USD") { |value| input["estimatedCost"] = value; check_options[:cost_explicit] = true }
          opts.on("--estimated-tokens TOKENS", Integer, "Estimated token count") { |value| input["estimatedTokens"] = value; check_options[:tokens_explicit] = true }
          opts.on("--key-source SOURCE", "Key provenance, such as codex_managed, company_managed, env, or personal") { |value| input["keySource"] = value }
          opts.on("--prompt TEXT", "Prompt text used to estimate Codex runs when cost/tokens are omitted") { |value| check_options[:prompt] = value }
          opts.on("--prompt-file PATH", "Read prompt text from PATH for Codex estimates") { |value| check_options[:prompt_file] = value }
          opts.on("--codex-hook-json", "Read Codex UserPromptSubmit JSON from stdin and estimate missing cost/tokens") { check_options[:codex_hook_json] = true }
          opts.on("--intent INTENT", "Run intent, such as refactor or debug") { |value| input["intent"] = value }
          opts.on("--json", "Print machine-readable JSON") { output_json = true }
          opts.on("-h", "--help", "Show help") do
            puts opts
            exit 0
          end
        end
        parser.parse!(argv)

        hook_payload = check_options[:codex_hook_json] ? read_stdin_json : {}
        apply_codex_prompt_payload!(input, check_options, hook_payload)
        config = load_config(options[:config_path])
        if input["agent"] == "codex" && !check_options[:provider_explicit]
          input["providerID"] = provider_from_model_or_agent(input["model"], input["agent"]) || input["providerID"]
        end
        apply_config_defaults!(input, config)
        attach_config_policy!(input, config)
        apply_codex_key_source_default!(input, check_options)
        estimate = apply_codex_preflight_estimate!(input, check_options, config)
        input["estimatedCost"] ||= 0.0
        input["estimatedTokens"] ||= 0
        validate_check_input!(input)

        response = post_policy_evaluate(options[:api_url], input)
        source = "local_api"
        fallback_reason = nil

        if response && config && response.dig("decision", "workspace", "id").to_s != input["workspaceID"].to_s
          fallback_reason = "local API evaluated workspace #{response.dig("decision", "workspace", "id").inspect}, not #{input["workspaceID"].inspect}"
          response = nil
        end

        unless response
          raise Error, "#{api_failure_message("policy checks require the app API")} and no tokenbar.yml was found" unless config

          response = offline_policy_response(input, config)
          source = "tokenbar_yml"
          fallback_reason ||= @last_api_error if @last_api_error
        end

        response["source"] = source
        response["configPath"] = config&.fetch("path", nil)
        response["fallbackReason"] = fallback_reason if fallback_reason
        response["preflightEstimate"] = estimate if estimate

        if output_json
          puts JSON.pretty_generate(response)
        else
          print_decision(response)
        end

        status = response.dig("decision", "status").to_s
        exit(EXIT_BY_STATUS.fetch(status, 3))
      end
    end
  end
end
