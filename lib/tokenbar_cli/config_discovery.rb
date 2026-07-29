# frozen_string_literal: true

module TokenBarCLI
  module ConfigDiscovery
    def infer_workspace_policy(cwd)
      signals = []
      signals.concat(codex_config_signals(cwd))
      signals.concat(claude_config_signals(cwd))
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

    def codex_config_signals(cwd = nil)
      config_paths(cwd, ".codex/config.toml", "~/.codex/config.toml").flat_map.with_index do |path, rank|
        next [] unless path.file?

        values = top_level_toml_values(path.read)
        model = values["model"]
        next [] if blank?(model)

        provider = provider_from_hint_or_model(values["model_provider"] || values["modelProvider"], model, "openai")
        [{ agent: "codex", provider: provider, model: model, path: path.to_s, rank: rank }]
      rescue SystemCallError
        []
      end
    end

    def claude_config_signals(cwd = nil)
      workspace_path = Pathname.new(cwd).expand_path.to_s if cwd
      paths = config_paths(cwd, ".claude/settings.json", "~/.claude/settings.json", "~/.claude/config.json")
      paths.flat_map do |path|
        next [] unless path.file?

        object = JSON.parse(path.read)
        model_strings(object).map do |model|
          {
            agent: "claudeCode",
            provider: provider_from_hint_or_model(nil, model, "anthropic"),
            model: model,
            path: path.to_s,
            rank: workspace_path && path.to_s.start_with?(workspace_path) ? 0 : 1
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
      ProviderCatalog.looks_like_model?(value)
    end

    def provider_from_hint_or_model(hint, model, fallback)
      ProviderCatalog.provider_for(hint: hint, model: model, fallback: fallback)
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

    def config_paths(cwd, *paths)
      expanded = paths.map do |path|
        if path.start_with?("~")
          Pathname.new(path).expand_path
        elsif cwd
          Pathname.new(cwd).expand_path.join(path)
        end
      end.compact
      expanded.uniq
    end
  end
end
