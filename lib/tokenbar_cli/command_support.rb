# frozen_string_literal: true

module TokenBarCLI
  module CommandSupport
    include Coercion

    def fetch_api_status(api_url)
      health = api_get(api_url, "/health").body
      policy = api_get(api_url, "/policy").body
      {
        "running" => !health.nil?,
        "url" => api_url,
        "health" => health,
        "policy" => policy
      }
    end

    def post_policy_evaluate(api_url, input)
      api_post(api_url, "/policy/evaluate", compact_hash(input))
    end

    def post_local_usage_ingest(api_url, input)
      api_post(api_url, "/usage/ingest", compact_hash(input))
    end

    def post_smart_routing_run(api_url, input)
      api_post(api_url, "/routing/runs", compact_hash(input))
    end

    def fetch_smart_routing_stats(api_url)
      api_get(api_url, "/routing/stats")
    end

    def api_post(api_url, path, input)
      api_session(api_url).post(path, input)
    end

    def api_get(api_url, path)
      api_session(api_url).get(path)
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
      fallback = agent == "claudeCode" ? "anthropic" : agent == "codex" ? "openai" : nil
      ProviderCatalog.provider_for(model: model, fallback: fallback)
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
      ProviderCatalog.default_model(provider)
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
      Coercion.integer(value, fallback)
    end

    def numeric_config(value, fallback)
      Coercion.numeric(value, fallback)
    end

    def blank?(value)
      Coercion.blank?(value)
    end
  end
end
