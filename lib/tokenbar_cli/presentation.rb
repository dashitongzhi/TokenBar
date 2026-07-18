# frozen_string_literal: true

module TokenBarCLI
  module Presentation
    def print_status(payload)
      api = payload["api"]
      config = payload["config"]
      if api["running"]
        health = api["health"] || {}
        puts "TokenBar API: running at #{api["url"]} (#{health["service"] || "unknown"})"
        decision = api.dig("policy", "decision")
        if decision
          workspace_name = decision.dig("workspace", "name") || "Workspace"
          puts "Current policy: #{decision["status"].to_s.upcase} #{workspace_name}"
        end
      else
        puts "TokenBar API: not running at #{api["url"]}"
      end

      if config
        workspace = config.dig("workspace", "name") || config.dig("workspace", "id") || "Workspace"
        puts "Config: #{config["path"]}"
        puts "Workspace: #{workspace}"
        puts "Allowed providers: #{Array(config.dig("providers", "allowed")).join(", ")}"
      else
        puts "Config: not found (searched upward for tokenbar.yml)"
      end
    end

    def print_decision(response)
      decision = response.fetch("decision")
      workspace_name = decision.dig("workspace", "name") || "Workspace"
      puts "#{decision["status"].to_s.upcase} #{workspace_name}"
      puts "Source: #{response["source"] == "local_api" ? "TokenBar local API" : "offline tokenbar.yml"}"
      puts
      puts "Reasons:"
      Array(decision["reasons"]).each { |reason| puts "- #{reason}" }
      puts
      puts "Recommendation:"
      puts decision["recommendation"]
      smart = decision["smartRouting"]
      return unless smart.is_a?(Hash)

      puts
      puts "Smart routing:"
      puts "- Route: #{smart["provider"]}/#{smart["model"]}"
      puts "- Confidence: #{(smart["confidence"].to_f * 100).round}% · evidence #{smart["evidenceRunCount"].to_i} runs · win rate #{(smart["winRate"].to_f * 100).round}%"
      puts "- Reason: #{smart["reason"]}"
    end

    def print_usage_ingest(response)
      usage = response.fetch("usage")
      decision = response.fetch("decision")
      puts "Ingested #{usage["dataSource"]} usage for #{usage["provider"]}"
      puts "Workspace: #{usage["workspaceID"] || "current app workspace"}"
      puts "Delta: $#{format_money(usage["costDelta"].to_f)} · #{usage["tokenDelta"].to_i} tokens"
      puts "Current policy: #{decision["status"].to_s.upcase} #{decision.dig("workspace", "name") || "Workspace"}"
    end

    def print_claude_statusline(response)
      usage = response.fetch("usage")
      decision = response.fetch("decision")
      workspace = decision.dig("workspace", "name") || usage["workspaceID"] || "Workspace"
      pieces = [
        "TokenBar #{decision["status"].to_s.upcase}",
        workspace,
        "$#{format_money(usage["costDelta"].to_f)}",
        "+#{usage["tokenDelta"].to_i}t"
      ]
      if usage["rateLimitUsedPercentage"]
        pieces << "#{usage["rateLimitUsedPercentage"].to_i}% limit"
      elsif usage["contextWindowSize"] && usage["contextWindowSize"].to_f.positive?
        ratio = usage["contextTokenTotal"].to_f / usage["contextWindowSize"].to_f
        pieces << "#{(ratio * 100).round}% ctx"
      end
      puts pieces.join(" · ")
    end

    def print_routing_record(response)
      run = response.fetch("routingRun")
      status = run["win"] ? "WIN" : run["signal"].to_s.upcase
      puts "Recorded routing run: #{status}"
      puts "Route: #{run["provider"]}/#{run["model"]} for #{run["taskIntent"]}"
      puts "Cost: estimated $#{format_money(run["estimatedCost"].to_f)} -> actual $#{format_money(run["actualCost"].to_f)}"
      puts "Tokens: estimated #{run["estimatedTokens"].to_i} -> actual #{run["actualTokens"].to_i}"
      puts "Workspace: #{run["workspaceName"] || run["workspaceID"] || "current app workspace"}"
    end

    def print_routing_stats(response)
      stats = response.fetch("stats")
      puts "Smart routing stats"
      puts "Runs: #{stats["totalRuns"]} | Win rate: #{percent(stats["winRate"])} | Follow-up rate: #{percent(stats["followUpRate"])}"
      puts "Cost: estimated $#{format_money(stats["estimatedCostTotal"].to_f)} -> actual $#{format_money(stats["actualCostTotal"].to_f)}"
      puts "Tokens: estimated #{stats["estimatedTokensTotal"].to_i} -> actual #{stats["actualTokensTotal"].to_i}"

      routes = Array(response["routes"]).first(5)
      return if routes.empty?

      puts
      puts "Top routes:"
      routes.each do |route|
        puts "- #{route["provider"]}/#{route["model"]} | #{route["taskIntent"]}: #{route["runCount"]} runs, #{percent(route["winRate"])} wins, #{percent(route["followUpRate"])} follow-up"
      end
    end

    def print_policy_init(payload)
      puts "Created TokenBar policy:"
      puts "- #{payload["policy"]}"

      unless payload["hooks"].empty?
        puts
        puts "Created hook config:"
        payload["written"].drop(1).each { |path| puts "- #{path}" }
      end

      smoke = payload["smokeDecision"]
      inference = payload["inference"] || {}
      if inference["source"] || inference[:source]
        source = inference["source"] || inference[:source]
        count = inference["configured_models"] || inference[:configured_models] || 0
        puts
        puts "Inferred defaults: #{source} (#{count} configured models)"
        puts "- providers: #{Array(inference["allowed_providers"] || inference[:allowed_providers]).join(", ")}"
        puts "- preferred: #{inference["preferred_provider"] || inference[:preferred_provider]} / #{inference["default_model"] || inference[:default_model]}"
        puts "- per-run cap: $#{format_money((inference["max_run"] || inference[:max_run]).to_f)}"
      end
      puts
      puts "Smoke check: #{smoke["status"].to_s.upcase}"
      Array(smoke["reasons"]).each { |reason| puts "- #{reason}" }
      puts
      config = load_config(payload["policy"])
      provider = config.dig("providers", "preferred")
      model = config.dig("models", "default") || default_model(provider)
      puts "Next: run tokenbar check --agent codex --provider #{provider} --model #{model}"
    end

    private

    def format_money(value)
      format("%.2f", value)
    end

    def percent(value)
      "#{(value.to_f * 100).round}%"
    end
  end
end
