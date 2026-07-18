# frozen_string_literal: true

module TokenBarCLI
  module CommandSupport
    def fetch_api_status(api_url)
      health = http_get(api_url, "/health")
      policy = http_get(api_url, "/policy")
      {
        "running" => !health.nil?,
        "url" => api_url,
        "health" => health,
        "policy" => policy
      }
    end

    def post_policy_evaluate(api_url, input)
      post_json(api_url, "/policy/evaluate", input)
    end

    def post_local_usage_ingest(api_url, input)
      post_json(api_url, "/usage/ingest", compact_hash(input))
    end

    def post_smart_routing_run(api_url, input)
      post_json(api_url, "/routing/runs", compact_hash(input))
    end

    def fetch_smart_routing_stats(api_url)
      http_get(api_url, "/routing/stats")
    end

    def post_json(api_url, path, input)
      client = local_api_client(api_url)
      response = client.post(path, input)
      @last_api_error = client.last_error
      response
    end

    def http_get(api_url, path)
      client = local_api_client(api_url)
      response = client.get(path)
      @last_api_error = client.last_error
      response
    end

    def api_failure_message(action)
      @last_api_client&.failure_message(action) || "TokenBar app is not running; #{action}"
    end

    def local_api_client(api_url)
      if @last_api_client.nil? || @last_api_client_url != api_url
        @last_api_client = LocalAPIClient.new(api_url, token_paths: LOCAL_API_TOKEN_PATHS)
        @last_api_client_url = api_url
      end
      @last_api_client
    end

    def repo_root
      Pathname.new(__dir__).parent.parent.expand_path
    end

    def split_list(value)
      value.to_s.split(",").map(&:strip).reject(&:empty?)
    end

    def parse_hooks(value)
      hooks = split_list(value).flat_map do |item|
        case item
        when "all" then %w[codex claude]
        when "none" then []
        else item
        end
      end.uniq
      invalid = hooks - %w[codex claude]
      raise Error, "--hooks must be codex, claude, all, or none" unless invalid.empty?

      hooks
    end

    def add_metadata!(metadata, value)
      key, separator, raw = value.to_s.partition("=")
      raise Error, "--metadata must use KEY=VALUE" if separator.empty? || key.strip.empty?

      metadata[key.strip] = raw.strip
    end

    def slug(value)
      slugged = value.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      slugged.empty? ? "workspace" : slugged
    end

    def titleize(value)
      words = value.tr("_-", " ").split
      return "Workspace" if words.empty?

      words.map { |word| word[0].upcase + word[1..].to_s }.join(" ")
    end

    def validate_usage_input!(input)
      valid_agents = AGENT_DISPLAY.keys
      raise Error, "--agent must be one of #{valid_agents.join(", ")}" unless valid_agents.include?(input["agent"])
      raise Error, "missing provider: pass --provider or set providers.preferred in tokenbar.yml" if blank?(input["providerID"])
      raise Error, "missing model: pass --model or set TOKENBAR_MODEL" if blank?(input["model"])
      raise Error, "--cost-usd must be >= 0" if input["costUSD"].to_f.negative?
      raise Error, "token counts must be >= 0" if %w[inputTokens outputTokens totalTokens requestCount].any? { |key| !input[key].nil? && input[key].to_i.negative? }
    end

    def validate_routing_input!(input)
      valid_agents = AGENT_DISPLAY.keys
      valid_signals = %w[success followUp failed unknown]
      input["signal"] = normalize_routing_signal(input["signal"])

      raise Error, "--agent must be one of #{valid_agents.join(", ")}" unless valid_agents.include?(input["agent"])
      raise Error, "missing provider: pass --provider or set providers.preferred in tokenbar.yml" if blank?(input["providerID"])
      raise Error, "missing model: pass --model or set TOKENBAR_MODEL" if blank?(input["model"])
      raise Error, "--signal must be one of #{valid_signals.join(", ")}" unless valid_signals.include?(input["signal"])

      numeric_keys = %w[estimatedCost actualCost estimatedTokens actualTokens inputTokens outputTokens requestCount]
      raise Error, "routing cost and token counts must be >= 0" if numeric_keys.any? { |key| !input[key].nil? && input[key].to_f.negative? }
    end

    def normalize_routing_signal(value)
      case value.to_s.strip.downcase.tr("_-", "")
      when "success", "succeeded", "win"
        "success"
      when "followup", "needsfollowup", "needsrepair"
        "followUp"
      when "failed", "failure", "fail"
        "failed"
      else
        "unknown"
      end
    end

    def provider_from_model_or_agent(model, agent)
      model = model.to_s.downcase
      return "anthropic" if model.include?("claude")
      return "openai" if model.include?("gpt") || model.match?(/\bo[134]\b/)
      return "minimax" if model.include?("minimax")
      return "deepseek" if model.include?("deepseek")
      return "google" if model.include?("gemini")
      return "mistral" if model.include?("mistral")
      return "kimi" if model.include?("kimi")
      return "xiaomi-mimo" if model.include?("mimo") || model.include?("xiaomi")
      return "glm" if model.include?("glm")
      return "qwen" if model.include?("qwen")
      return "anthropic" if agent == "claudeCode"
      return "openai" if agent == "codex"

      nil
    end

    def validate_check_input!(input)
      valid_agents = AGENT_DISPLAY.keys
      raise Error, "--agent must be one of #{valid_agents.join(", ")}" unless valid_agents.include?(input["agent"])
      raise Error, "missing provider: pass --provider or set providers.preferred in tokenbar.yml" if blank?(input["providerID"])
      raise Error, "missing model: pass --model or set TOKENBAR_MODEL" if blank?(input["model"])
      raise Error, "--estimated-cost must be >= 0" if input["estimatedCost"].to_f.negative?
      raise Error, "--estimated-tokens must be >= 0" if input["estimatedTokens"].to_i.negative?
    end

    def default_model(provider)
      case provider
      when "anthropic" then "claude-sonnet"
      when "openai" then "gpt-5"
      when "minimax" then "minimax-m1"
      when "deepseek" then "deepseek-chat"
      when "google" then "gemini-2.5-pro"
      when "mistral" then "mistral-large-latest"
      when "kimi" then "kimi-k2"
      when "glm" then "glm-4.5"
      else "unspecified"
      end
    end

    def offline_policy_response(input, config)
      OfflinePolicy.evaluate(input, config, agent_display: AGENT_DISPLAY)
    end

    def offline_workspace(config, workspace_id)
      OfflinePolicy.workspace(config, workspace_id)
    end

    def config_summary(config)
      return nil unless config

      workspace = config.fetch("workspace", {})
      budgets = config.fetch("budgets", {})
      providers = config.fetch("providers", {})
      models = config.fetch("models", {})
      rules = config.fetch("rules", {})
      {
        "path" => config["path"],
        "workspace" => {
          "id" => workspace["id"],
          "name" => workspace["name"],
          "path" => workspace["path"] || workspace["pathHint"]
        },
        "budgets" => budgets.slice("daily", "monthly", "max_run", "spend_today"),
        "providers" => {
          "allowed" => providers["allowed"],
          "preferred" => providers["preferred"],
          "requireCompanyKey" => providers["require_company_key"] || providers["requireCompanyKey"] || false
        },
        "models" => {
          "default" => models["default"],
          "blocked" => models["blocked"]
        },
        "rules" => rules.slice("max_estimated_tokens", "maxEstimatedTokens")
      }
    end

    def numeric_env(name, fallback)
      value = ENV[name]
      return fallback if blank?(value)

      Float(value)
    rescue ArgumentError
      fallback
    end

    def integer_env(name, fallback)
      value = ENV[name]
      return fallback if blank?(value)

      Integer(value)
    rescue ArgumentError
      fallback
    end

    def integer_config(value, fallback)
      return fallback if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      fallback
    end

    def numeric_config(value, fallback)
      return fallback if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      fallback
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
