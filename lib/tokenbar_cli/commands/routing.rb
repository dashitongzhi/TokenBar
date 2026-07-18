# frozen_string_literal: true

module TokenBarCLI
  module Commands
    module Routing
      def routing(options, argv)
        subcommand = argv.shift
        raise Error, "missing routing command: use record or stats" unless subcommand

        case subcommand
        when "record"
          routing_record(options, argv)
        when "stats"
          routing_stats(options, argv)
        else
          raise Error, "unknown routing command: #{subcommand}"
        end
      end

      def routing_record(options, argv)
        input = {
          "agent" => ENV.fetch("TOKENBAR_AGENT", "custom"),
          "taskIntent" => ENV.fetch("TOKENBAR_INTENT", "unspecified"),
          "providerID" => ENV["TOKENBAR_PROVIDER"],
          "model" => ENV["TOKENBAR_MODEL"],
          "workspaceID" => nil,
          "workspaceName" => nil,
          "workspacePath" => Dir.pwd,
          "sessionID" => ENV["TOKENBAR_SESSION_ID"],
          "taskID" => ENV["TOKENBAR_TASK_ID"],
          "estimatedCost" => numeric_env("TOKENBAR_ESTIMATED_COST", 0.0),
          "actualCost" => numeric_env("TOKENBAR_ACTUAL_COST", numeric_env("TOKENBAR_COST_USD", 0.0)),
          "estimatedTokens" => integer_env("TOKENBAR_ESTIMATED_TOKENS", 0),
          "actualTokens" => integer_env("TOKENBAR_ACTUAL_TOKENS", nil),
          "inputTokens" => integer_env("TOKENBAR_INPUT_TOKENS", nil),
          "outputTokens" => integer_env("TOKENBAR_OUTPUT_TOKENS", nil),
          "requestCount" => integer_env("TOKENBAR_REQUEST_COUNT", nil),
          "signal" => ENV.fetch("TOKENBAR_ROUTING_SIGNAL", "unknown"),
          "followUpRequired" => nil,
          "selectedBy" => ENV["TOKENBAR_SELECTED_BY"],
          "alternatives" => split_list(ENV["TOKENBAR_ALTERNATIVES"].to_s),
          "routingReason" => ENV["TOKENBAR_ROUTING_REASON"],
          "metadata" => {}
        }
        output_json = options[:json]

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: tokenbar routing record --intent INTENT --provider PROVIDER --model MODEL [options]"
          opts.on("--agent AGENT", "claudeCode, codex, cursor, continueDev, or custom") { |value| input["agent"] = value }
          opts.on("--intent INTENT", "Task intent, such as bugfix, refactor, research, or implementation") { |value| input["taskIntent"] = value }
          opts.on("--provider PROVIDER", "Selected provider id") { |value| input["providerID"] = value }
          opts.on("--model MODEL", "Selected model id") { |value| input["model"] = value }
          opts.on("--workspace-id ID", "Workspace id") { |value| input["workspaceID"] = value }
          opts.on("--workspace-name NAME", "Workspace display name") { |value| input["workspaceName"] = value }
          opts.on("--cwd PATH", "Workspace path") { |value| input["workspacePath"] = value }
          opts.on("--session-id ID", "Agent session id") { |value| input["sessionID"] = value }
          opts.on("--task-id ID", "Stable task id") { |value| input["taskID"] = value }
          opts.on("--estimated-cost USD", Float, "Estimated run cost in USD") { |value| input["estimatedCost"] = value }
          opts.on("--actual-cost USD", Float, "Actual run cost in USD") { |value| input["actualCost"] = value }
          opts.on("--estimated-tokens TOKENS", Integer, "Estimated token count") { |value| input["estimatedTokens"] = value }
          opts.on("--actual-tokens TOKENS", Integer, "Actual token count") { |value| input["actualTokens"] = value }
          opts.on("--input-tokens TOKENS", Integer, "Actual input tokens") { |value| input["inputTokens"] = value }
          opts.on("--output-tokens TOKENS", Integer, "Actual output tokens") { |value| input["outputTokens"] = value }
          opts.on("--request-count COUNT", Integer, "Actual request count") { |value| input["requestCount"] = value }
          opts.on("--success", "Mark the route as successful") { input["signal"] = "success"; input["followUpRequired"] = false }
          opts.on("--follow-up", "Mark the route as requiring follow-up") { input["signal"] = "followUp"; input["followUpRequired"] = true }
          opts.on("--failed", "Mark the route as failed") { input["signal"] = "failed"; input["followUpRequired"] = true }
          opts.on("--signal SIGNAL", "success, followUp, failed, or unknown") { |value| input["signal"] = value }
          opts.on("--selected-by NAME", "Router or policy that selected the provider/model") { |value| input["selectedBy"] = value }
          opts.on("--alternatives LIST", "Comma-separated provider/model alternatives considered") { |value| input["alternatives"] = split_list(value) }
          opts.on("--routing-reason TEXT", "Short explanation for the route") { |value| input["routingReason"] = value }
          opts.on("--metadata KEY=VALUE", "Attach metadata; may be repeated") { |value| add_metadata!(input["metadata"], value) }
          opts.on("--json", "Print machine-readable JSON") { output_json = true }
          opts.on("-h", "--help", "Show help") do
            puts opts
            exit 0
          end
        end
        parser.parse!(argv)

        config = load_config(options[:config_path])
        input["providerID"] ||= provider_from_model_or_agent(input["model"], input["agent"])
        input["model"] ||= default_model(input["providerID"])
        input["actualTokens"] ||= input["inputTokens"].to_i + input["outputTokens"].to_i if input["inputTokens"] || input["outputTokens"]
        attach_routing_config!(input, config)
        validate_routing_input!(input)

        response = post_smart_routing_run(options[:api_url], input)
        raise Error, api_failure_message("smart routing run recording requires the app API") unless response

        if output_json
          puts JSON.pretty_generate(response)
        else
          print_routing_record(response)
        end
      end

      def routing_stats(options, argv)
        output_json = options[:json]
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: tokenbar routing stats [--json]"
          opts.on("--json", "Print machine-readable JSON") { output_json = true }
          opts.on("-h", "--help", "Show help") do
            puts opts
            exit 0
          end
        end
        parser.parse!(argv)

        response = fetch_smart_routing_stats(options[:api_url])
        raise Error, api_failure_message("smart routing stats require the app API") unless response

        if output_json
          puts JSON.pretty_generate(response)
        else
          print_routing_stats(response)
        end
      end
    end
  end
end
