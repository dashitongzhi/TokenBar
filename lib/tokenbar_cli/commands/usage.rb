# frozen_string_literal: true

module TokenBarCLI
  module Commands
    module Usage
      def usage(options, argv)
        subcommand = argv.shift
        raise Error, "missing usage command: use ingest, claude-statusline, or codex-session" unless subcommand

        case subcommand
        when "ingest"
          usage_ingest(options, argv)
        when "claude-statusline"
          usage_claude_statusline(options, argv)
        when "codex-session"
          usage_codex_session(options, argv)
        else
          raise Error, "unknown usage command: #{subcommand}"
        end
      end

      def usage_ingest(options, argv)
        input = {
          "agent" => ENV.fetch("TOKENBAR_AGENT", "custom"),
          "providerID" => ENV["TOKENBAR_PROVIDER"],
          "model" => ENV["TOKENBAR_MODEL"],
          "workspaceID" => nil,
          "sessionID" => ENV["TOKENBAR_SESSION_ID"],
          "source" => "tokenbar_cli",
          "currentDirectory" => Dir.pwd,
          "costUSD" => numeric_env("TOKENBAR_COST_USD", 0.0),
          "inputTokens" => integer_env("TOKENBAR_INPUT_TOKENS", 0),
          "outputTokens" => integer_env("TOKENBAR_OUTPUT_TOKENS", 0),
          "totalTokens" => nil,
          "requestCount" => nil,
          "cumulative" => true
        }
        output_json = options[:json]

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: tokenbar usage ingest --agent AGENT --provider PROVIDER --model MODEL [options]"
          opts.on("--agent AGENT", "claudeCode, codex, cursor, continueDev, or custom") { |value| input["agent"] = value }
          opts.on("--workspace-id ID", "Workspace id (default: tokenbar.yml workspace id)") { |value| input["workspaceID"] = value }
          opts.on("--provider PROVIDER", "Provider id, such as anthropic or openai") { |value| input["providerID"] = value }
          opts.on("--model MODEL", "Model name or slug") { |value| input["model"] = value }
          opts.on("--session-id ID", "Stable local agent session id") { |value| input["sessionID"] = value }
          opts.on("--source NAME", "Usage source label") { |value| input["source"] = value }
          opts.on("--cwd PATH", "Workspace path reported by the local agent") { |value| input["currentDirectory"] = value }
          opts.on("--cost-usd USD", Float, "Cumulative session cost in USD") { |value| input["costUSD"] = value }
          opts.on("--input-tokens TOKENS", Integer, "Cumulative input tokens") { |value| input["inputTokens"] = value }
          opts.on("--output-tokens TOKENS", Integer, "Cumulative output tokens") { |value| input["outputTokens"] = value }
          opts.on("--total-tokens TOKENS", Integer, "Cumulative total tokens") { |value| input["totalTokens"] = value }
          opts.on("--request-count COUNT", Integer, "Cumulative request count") { |value| input["requestCount"] = value }
          opts.on("--context-window-size TOKENS", Integer, "Context window token limit") { |value| input["contextWindowSize"] = value }
          opts.on("--event", "Treat cost/tokens as this event only, not cumulative session totals") { input["cumulative"] = false }
          opts.on("--json", "Print machine-readable JSON") { output_json = true }
          opts.on("-h", "--help", "Show help") do
            puts opts
            exit 0
          end
        end
        parser.parse!(argv)

        config = load_config(options[:config_path])
        attach_config_policy!(input, config)
        input["providerID"] ||= provider_from_model_or_agent(input["model"], input["agent"])
        input["model"] ||= default_model(input["providerID"])
        input["totalTokens"] ||= input["inputTokens"].to_i + input["outputTokens"].to_i
        validate_usage_input!(input)

        response = post_local_usage_ingest(options[:api_url], input)
        raise Error, api_failure_message("local usage ingestion requires the app API") unless response

        if output_json
          puts JSON.pretty_generate(response)
        else
          print_usage_ingest(response)
        end
      end

      def usage_claude_statusline(options, argv)
        output_json = options[:json]
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: tokenbar usage claude-statusline [--json]"
          opts.on("--json", "Print machine-readable JSON instead of a statusline string") { output_json = true }
          opts.on("-h", "--help", "Show help") do
            puts opts
            exit 0
          end
        end
        parser.parse!(argv)

        raw = STDIN.read
        payload = JSON.parse(raw)
        input = claude_statusline_usage_input(payload)
        config = load_config(options[:config_path])
        attach_config_policy!(input, config)
        input["providerID"] ||= provider_from_model_or_agent(input["model"], input["agent"])
        input["model"] ||= default_model(input["providerID"])
        validate_usage_input!(input)

        response = post_local_usage_ingest(options[:api_url], input)
        raise Error, api_failure_message("Claude Code statusline ingestion requires the app API") unless response

        if output_json
          puts JSON.pretty_generate(response)
        else
          print_claude_statusline(response)
        end
      rescue JSON::ParserError => e
        raise Error, "invalid Claude Code statusline JSON: #{e.message}"
      end

      def usage_codex_session(options, argv)
        codex_options = {
          transcript: ENV["TOKENBAR_CODEX_TRANSCRIPT"],
          session_id: ENV["TOKENBAR_SESSION_ID"],
          cwd: ENV["TOKENBAR_WORKSPACE_PATH"],
          model: ENV["TOKENBAR_MODEL"]
        }
        output_json = options[:json]

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: tokenbar usage codex-session [--transcript PATH] [--json]"
          opts.on("--transcript PATH", "Codex transcript JSONL path") { |value| codex_options[:transcript] = value }
          opts.on("--session-id ID", "Stable Codex session id") { |value| codex_options[:session_id] = value }
          opts.on("--cwd PATH", "Workspace path reported by Codex") { |value| codex_options[:cwd] = value }
          opts.on("--model MODEL", "Codex model id") { |value| codex_options[:model] = value }
          opts.on("--json", "Print machine-readable JSON") { output_json = true }
          opts.on("-h", "--help", "Show help") do
            puts opts
            exit 0
          end
        end
        parser.parse!(argv)

        hook_payload = read_stdin_json
        config = load_config(options[:config_path])
        input = codex_session_usage_input(hook_payload, codex_options, config)
        attach_config_policy!(input, config)
        validate_usage_input!(input)

        response = post_local_usage_ingest(options[:api_url], input)
        raise Error, api_failure_message("Codex local usage ingestion requires the app API") unless response

        if output_json
          puts JSON.pretty_generate(response)
        else
          print_usage_ingest(response)
        end
      end
    end
  end
end
