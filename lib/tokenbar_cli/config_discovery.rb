# frozen_string_literal: true

module TokenBarCLI
  module ConfigDiscovery
    def infer_workspace_policy(cwd)
      signals = []
      signals.concat(codex_config_signals)
      signals.concat(claude_config_signals)
      signals.concat(cc_switch_config_signals)
      signals = signals.select { |signal| !blank?(signal[:provider]) && !blank?(signal[:model]) }
      preferred = signals.min_by { |signal| [signal[:rank], signal[:model].to_s] }
      allowed = ordered_unique(signals.map { |signal| policy_provider_id(signal[:provider]) })
      allowed = %w[openai anthropic openrouter] if allowed.empty?
      preferred_provider = policy_provider_id(preferred&.fetch(:provider, nil)) || allowed.first || "openai"
      default_model_value = preferred&.fetch(:model, nil) || default_model(preferred_provider)
      blocked_models = %w[opus gpt-5-pro].reject do |blocked|
        signals.any? { |signal| signal[:model].to_s.downcase.include?(blocked) }
      end
      paths = ordered_unique(signals.map { |signal| signal[:path] }.compact)

      {
        allowed_providers: allowed,
        preferred_provider: preferred_provider,
        default_model: default_model_value,
        max_run: default_per_run_cap(preferred_provider, default_model_value),
        blocked_models: blocked_models,
        configured_models: signals.length,
        paths: paths,
        source: paths.empty? ? "fallback_defaults" : "local_agent_config"
      }
    end

    def codex_config_signals
      path = Pathname.new("~/.codex/config.toml").expand_path
      return [] unless path.file?

      values = top_level_toml_values(path.read)
      model = values["model"]
      return [] if blank?(model)

      provider = provider_from_hint_or_model(values["model_provider"] || values["modelProvider"], model, "openai")
      [{ agent: "codex", provider: provider, model: model, path: path.to_s, rank: 0 }]
    rescue SystemCallError
      []
    end

    def claude_config_signals
      paths = [
        Pathname.new("~/.claude/settings.json").expand_path,
        Pathname.new("~/.claude/config.json").expand_path
      ]
      paths.flat_map do |path|
        next [] unless path.file?

        object = JSON.parse(path.read)
        model_strings(object).map do |model|
          {
            agent: "claudeCode",
            provider: provider_from_hint_or_model(nil, model, "anthropic"),
            model: model,
            path: path.to_s,
            rank: 1
          }
        end
      rescue JSON::ParserError, SystemCallError
        []
      end
    end

    def cc_switch_config_signals
      database = Pathname.new("~/.cc-switch/cc-switch.db").expand_path
      return [] unless database.file?

      stdout, _stderr, status = Open3.capture3(
        "sqlite3",
        "-json",
        database.to_s,
        "select id, app_type, name, settings_config from providers"
      )
      return [] unless status.success?

      JSON.parse(stdout).flat_map do |row|
        config = JSON.parse(row["settings_config"].to_s)
        models = model_strings(config)
        models.map do |model|
          provider = provider_from_hint_or_model(
            [row["id"], row["app_type"], row["name"], config["baseURL"], config["baseUrl"], config["base_url"]].compact.join(" "),
            model,
            row["app_type"] == "codex" ? "openai" : "custom"
          )
          {
            agent: row["app_type"],
            provider: provider,
            model: model,
            path: database.to_s,
            rank: 2
          }
        end
      end
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def top_level_toml_values(content)
      values = {}
      in_top_level = true
      content.each_line do |raw_line|
        line = raw_line.split("#", 2).first.to_s.strip
        next if line.empty?
        if line.start_with?("[")
          in_top_level = false
          next
        end
        next unless in_top_level
        key, raw_value = line.split("=", 2).map { |part| part&.strip }
        next if blank?(key) || blank?(raw_value)

        values[key] = raw_value.gsub(/\A["']|["']\z/, "")
      end
      values
    end

    def model_strings(value)
      models = []
      walk_model_strings(value, models)
      ordered_unique(models).select { |model| looks_like_model?(model) }
    end

    def walk_model_strings(value, models)
      case value
      when Hash
        value.each do |key, child|
          normalized = key.to_s.downcase.tr("_-", "")
          if child.is_a?(String) && %w[model modelid modelname defaultmodel].include?(normalized)
            models << child
          elsif normalized == "env" && child.is_a?(Hash)
            child.each do |env_key, env_value|
              next unless env_value.is_a?(String)
              next unless %w[ANTHROPIC_MODEL CLAUDE_MODEL OPENAI_MODEL CODEX_MODEL].include?(env_key.to_s.upcase)

              models << env_value
            end
          end
          walk_model_strings(child, models)
        end
      when Array
        value.each { |child| walk_model_strings(child, models) }
      end
    end

    def looks_like_model?(value)
      normalized = value.to_s.strip.downcase
      return false if normalized.length < 2 || normalized.length > 120

      %w[claude gpt o1 o3 o4 gemini deepseek minimax mistral kimi mimo xiaomi glm qwen].any? do |marker|
        normalized.include?(marker)
      end
    end

    def provider_from_hint_or_model(hint, model, fallback)
      haystack = [hint, model].compact.join(" ").downcase
      return "anthropic" if haystack.include?("anthropic") || haystack.include?("claude")
      return "openai" if haystack.include?("openai") || haystack.include?("gpt") || haystack.match?(/\bo[134]\b/)
      return "openrouter" if haystack.include?("openrouter")
      return "minimax" if haystack.include?("minimax")
      return "deepseek" if haystack.include?("deepseek")
      return "google" if haystack.include?("gemini") || haystack.include?("google")
      return "mistral" if haystack.include?("mistral")
      return "kimi" if haystack.include?("kimi")
      return "xiaomi-mimo" if haystack.include?("mimo") || haystack.include?("xiaomi")
      return "glm" if haystack.include?("glm")
      return "qwen" if haystack.include?("qwen")

      fallback
    end

    def policy_provider_id(provider)
      return nil if blank?(provider)

      case provider
      when "codex", "ccswitch-codex"
        "openai"
      else
        provider
      end
    end

    def default_per_run_cap(provider, model)
      normalized = "#{provider} #{model}".downcase
      return 2.50 if normalized.include?("pro") || normalized.include?("opus")
      return 0.75 if normalized.match?(/mini|haiku|deepseek|minimax|kimi|glm/)

      1.50
    end

    def ordered_unique(values)
      seen = {}
      values.each_with_object([]) do |value, memo|
        item = value.to_s.strip
        next if item.empty? || seen[item]

        seen[item] = true
        memo << item
      end
    end
  end
end
