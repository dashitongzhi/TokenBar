# frozen_string_literal: true

module TokenBarCLI
  module_function

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

  def load_config(explicit_path)
    path = explicit_path ? Pathname.new(explicit_path).expand_path : find_config(Pathname.pwd)
    return nil unless path&.file?

    data = YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: false) || {}
    normalize_keys(data).merge("path" => path.to_s)
  rescue Psych::SyntaxError => e
    raise Error, "invalid YAML in #{path}: #{e.message}"
  end

  def find_config(start)
    cursor = start.expand_path
    loop do
      CONFIG_NAMES.each do |name|
        candidate = cursor.join(name)
        return candidate if candidate.file?
      end
      parent = cursor.parent
      return nil if parent == cursor

      cursor = parent
    end
  end

  def normalize_keys(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, item), memo| memo[key.to_s] = normalize_keys(item) }
    when Array
      value.map { |item| normalize_keys(item) }
    else
      value
    end
  end

  def apply_config_defaults!(input, config)
    workspace = config&.fetch("workspace", {}) || {}
    providers = config&.fetch("providers", {}) || {}
    allowed = Array(providers["allowed"]).compact

    input["workspaceID"] ||= workspace["id"] || File.basename(Dir.pwd)
    input["providerID"] ||= providers["preferred"] || allowed.first
    input["model"] ||= config&.dig("models", "default") || default_model(input["providerID"])
  end

  def attach_config_policy!(input, config)
    return input unless config

    workspace = offline_workspace(config, input["workspaceID"] || config.dig("workspace", "id"))
    input["workspaceID"] ||= workspace["id"]
    input["workspaceName"] = workspace["name"]
    input["workspacePath"] = workspace["pathHint"]
    input["workspaceClient"] = workspace["client"]
    input["dailyBudget"] = workspace["dailyBudget"]
    input["monthlyBudget"] = workspace["monthlyBudget"]
    input["maxEstimatedRunCost"] = workspace["maxEstimatedRunCost"]
    input["maxEstimatedTokens"] = workspace["maxEstimatedTokens"]
    input["allowedProviderIDs"] = workspace["allowedProviderIDs"]
    input["blockedModels"] = workspace["blockedModels"]
    input["requireCompanyKey"] = workspace["requireCompanyKey"]
    input["providerID"] ||= config.dig("providers", "preferred") || workspace["allowedProviderIDs"].first
    input["model"] ||= config.dig("models", "default") || default_model(input["providerID"])
    input["preferredProviderID"] = config.dig("providers", "preferred")
    input["preferredModel"] = config.dig("models", "default")
    input
  end

  def attach_routing_config!(input, config)
    return input unless config

    workspace = offline_workspace(config, input["workspaceID"] || config.dig("workspace", "id"))
    input["workspaceID"] ||= workspace["id"]
    input["workspaceName"] ||= workspace["name"]
    input["workspacePath"] ||= workspace["pathHint"]
    input["providerID"] ||= config.dig("providers", "preferred") || workspace["allowedProviderIDs"].first
    input
  end
end
