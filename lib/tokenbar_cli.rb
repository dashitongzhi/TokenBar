#!/usr/bin/ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "net/http"
require "open3"
require "optparse"
require "pathname"
require "time"
require "uri"
require "yaml"

module TokenBarCLI
  DEFAULT_API_URL = "http://127.0.0.1:3847"
  CONFIG_NAMES = %w[tokenbar.yml tokenbar.yaml].freeze
  EXIT_BY_STATUS = { "allow" => 0, "warn" => 1, "block" => 2 }.freeze
  AGENT_DISPLAY = {
    "claudeCode" => "Claude Code",
    "codex" => "Codex",
    "cursor" => "Cursor",
    "continueDev" => "Continue",
    "custom" => "Custom Agent"
  }.freeze

  class Error < StandardError; end

  module_function

  def main(argv)
    options = {
      api_url: ENV.fetch("TOKENBAR_API_URL", DEFAULT_API_URL),
      config_path: nil,
      json: false
    }

    global = OptionParser.new do |opts|
      opts.banner = "Usage: tokenbar [--api-url URL] [--config PATH] <status|check|policy> [options]"
      opts.on("--api-url URL", "TokenBar local API URL (default: #{DEFAULT_API_URL})") { |value| options[:api_url] = value }
      opts.on("--config PATH", "Use a specific tokenbar.yml instead of upward lookup") { |value| options[:config_path] = value }
      opts.on("--json", "Print machine-readable JSON") { options[:json] = true }
      opts.on("-h", "--help", "Show help") do
        puts opts
        exit 0
      end
    end
    global.order!(argv)

    command = argv.shift
    raise Error, "missing command: use status, check, or policy" unless command

    case command
    when "status"
      status(options, argv)
    when "check"
      check(options, argv)
    when "policy"
      policy(options, argv)
    else
      raise Error, "unknown command: #{command}"
    end
  rescue Error => e
    warn "tokenbar: #{e.message}"
    exit 3
  rescue OptionParser::ParseError => e
    warn "tokenbar: #{e.message}"
    exit 3
  end

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
      "estimatedCost" => numeric_env("TOKENBAR_ESTIMATED_COST", 0.0),
      "estimatedTokens" => integer_env("TOKENBAR_ESTIMATED_TOKENS", 0),
      "intent" => ENV.fetch("TOKENBAR_INTENT", "unspecified")
    }
    output_json = options[:json]

    parser = OptionParser.new do |opts|
      opts.banner = "Usage: tokenbar check --agent AGENT --provider PROVIDER --model MODEL [options]"
      opts.on("--agent AGENT", "claudeCode, codex, cursor, continueDev, or custom") { |value| input["agent"] = value }
      opts.on("--workspace-id ID", "Override tokenbar.yml workspace id") { |value| input["workspaceID"] = value }
      opts.on("--provider PROVIDER", "Provider id, such as anthropic or openai") { |value| input["providerID"] = value }
      opts.on("--model MODEL", "Model name or slug") { |value| input["model"] = value }
      opts.on("--estimated-cost COST", Float, "Estimated run cost in USD") { |value| input["estimatedCost"] = value }
      opts.on("--estimated-tokens TOKENS", Integer, "Estimated token count") { |value| input["estimatedTokens"] = value }
      opts.on("--intent INTENT", "Run intent, such as refactor or debug") { |value| input["intent"] = value }
      opts.on("--json", "Print machine-readable JSON") { output_json = true }
      opts.on("-h", "--help", "Show help") do
        puts opts
        exit 0
      end
    end
    parser.parse!(argv)

    config = load_config(options[:config_path])
    apply_config_defaults!(input, config)
    validate_check_input!(input)

    response = post_policy_evaluate(options[:api_url], input)
    source = "local_api"
    fallback_reason = nil

    if response && config && response.dig("decision", "workspace", "id").to_s != input["workspaceID"].to_s
      fallback_reason = "local API evaluated workspace #{response.dig("decision", "workspace", "id").inspect}, not #{input["workspaceID"].inspect}"
      response = nil
    end

    unless response
      raise Error, "TokenBar app is not running and no tokenbar.yml was found" unless config

      response = offline_policy_response(input, config)
      source = "tokenbar_yml"
    end

    response["source"] = source
    response["configPath"] = config&.fetch("path", nil)
    response["fallbackReason"] = fallback_reason if fallback_reason

    if output_json
      puts JSON.pretty_generate(response)
    else
      print_decision(response)
    end

    status = response.dig("decision", "status").to_s
    exit(EXIT_BY_STATUS.fetch(status, 3))
  end

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
    init_options = {
      output: cwd.join("tokenbar.yml"),
      workspace_id: slug(cwd.basename.to_s),
      workspace_name: titleize(cwd.basename.to_s),
      workspace_path: cwd.to_s,
      client: "local",
      daily_budget: 8.00,
      monthly_budget: 160.00,
      max_run: 1.50,
      spend_today: 0.00,
      spend_month: 0.00,
      allowed_providers: %w[anthropic openai openrouter],
      preferred_provider: "anthropic",
      require_company_key: false,
      blocked_models: %w[opus gpt-5-pro],
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
      opts.on("--max-run-cost USD", Float, "Per-run cost cap in USD (default: 1.50)") { |value| init_options[:max_run] = value }
      opts.on("--allowed-providers LIST", "Comma-separated providers (default: anthropic,openai,openrouter)") { |value| init_options[:allowed_providers] = split_list(value) }
      opts.on("--preferred-provider PROVIDER", "Preferred provider (default: anthropic)") { |value| init_options[:preferred_provider] = value }
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
      "model" => default_model(init_options[:preferred_provider]),
      "estimatedCost" => 0.0,
      "estimatedTokens" => 0,
      "intent" => "policy_init_smoke"
    }
    decision = offline_policy_response(sample_input, config).fetch("decision")

    payload = {
      "policy" => init_options[:output].to_s,
      "hooks" => init_options[:hooks],
      "written" => written,
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
    uri = endpoint(api_url, "/policy/evaluate")
    if curl_available?
      body = curl_request(["-X", "POST", "-H", "Content-Type: application/json", "--data", JSON.generate(input), uri.to_s])
      return body ? JSON.parse(body) : nil
    end

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(input)
    response = http_request(uri, request)
    return nil unless response&.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError
    nil
  end

  def http_get(api_url, path)
    uri = endpoint(api_url, path)
    if curl_available?
      body = curl_request([uri.to_s])
      return body ? JSON.parse(body) : nil
    end

    response = http_request(uri, Net::HTTP::Get.new(uri))
    return nil unless response&.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError
    nil
  end

  def curl_available?
    @curl_available = system("command -v curl >/dev/null 2>&1") if @curl_available.nil?
    @curl_available
  end

  def curl_request(args)
    stdout, _stderr, status = Open3.capture3("curl", "-fsS", "--max-time", "2", *args)
    return nil unless status.success?

    stdout
  end

  def http_request(uri, request)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 0.5, read_timeout: 1.5) do |http|
      http.request(request)
    end
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError, Net::OpenTimeout, Net::ReadTimeout
    nil
  end

  def endpoint(api_url, path)
    base = URI(api_url)
    base.path = path
    base.query = nil
    base
  end

  def repo_root
    Pathname.new(__dir__).parent.expand_path
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

  def slug(value)
    slugged = value.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
    slugged.empty? ? "workspace" : slugged
  end

  def titleize(value)
    words = value.tr("_-", " ").split
    return "Workspace" if words.empty?

    words.map { |word| word[0].upcase + word[1..].to_s }.join(" ")
  end

  def validate_init_options!(options)
    raise Error, "--workspace-id cannot be empty" if blank?(options[:workspace_id])
    raise Error, "--workspace-name cannot be empty" if blank?(options[:workspace_name])
    raise Error, "--daily-budget must be >= 0" if options[:daily_budget].negative?
    raise Error, "--monthly-budget must be >= 0" if options[:monthly_budget].negative?
    raise Error, "--max-run-cost must be > 0" unless options[:max_run].positive?
    raise Error, "--allowed-providers cannot be empty" if options[:allowed_providers].empty?
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
      "providers:",
      "  allowed:",
      *options[:allowed_providers].map { |provider| "    - #{yaml_scalar(provider)}" },
      "  preferred: #{yaml_scalar(options[:preferred_provider])}",
      "  require_company_key: #{options[:require_company_key] ? "true" : "false"}",
      "",
      "models:"
    ]
    if options[:blocked_models].empty?
      lines << "  blocked: []"
    else
      lines << "  blocked:"
      lines.concat(options[:blocked_models].map { |model| "    - #{yaml_scalar(model)}" })
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
            ]
          }
        ) + "\n"
      ]
    when "claude"
      [
        cwd.join(".claude/settings.local.json"),
        JSON.pretty_generate(
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
    input["model"] ||= default_model(input["providerID"])
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
    else "unspecified"
    end
  end

  def offline_policy_response(input, config)
    workspace = offline_workspace(config, input["workspaceID"])
    projected_daily_spend = workspace["spendToday"].to_f + input["estimatedCost"].to_f
    status = "allow"
    reasons = []

    unless workspace["allowedProviderIDs"].include?(input["providerID"])
      status = "block"
      reasons << "Provider is not allowed for this workspace."
    end

    if workspace["blockedModels"].any? { |blocked| input["model"].to_s.downcase.include?(blocked.to_s.downcase) }
      status = "block"
      reasons << "Model is blocked by the workspace policy."
    end

    if input["estimatedCost"].to_f > workspace["maxEstimatedRunCost"].to_f
      status = "block"
      reasons << "Estimated run cost is above the per-run cap."
    end

    if workspace["requireCompanyKey"] && input["providerID"] == "openai"
      status = "block"
      reasons << "Workspace requires a company-managed key."
    end

    daily_budget = workspace["dailyBudget"].to_f
    if daily_budget.positive? && projected_daily_spend >= daily_budget
      status = "block"
      reasons << "Projected daily spend would exceed the workspace budget."
    elsif daily_budget.positive? && projected_daily_spend >= daily_budget * 0.8 && status != "block"
      status = "warn"
      reasons << "Projected daily spend is close to the workspace budget."
    end

    reasons << "Workspace, provider, model, and budget are inside policy." if reasons.empty?
    fallback = workspace["allowedProviderIDs"].find { |provider| provider != input["providerID"] }
    recommendation = recommendation(status, input["model"], fallback)

    {
      "version" => "1.0",
      "timestamp" => Time.now.utc.iso8601,
      "localOnly" => true,
      "offline" => true,
      "decision" => {
        "status" => status,
        "agent" => AGENT_DISPLAY.fetch(input["agent"], input["agent"]),
        "workspace" => {
          "id" => workspace["id"],
          "name" => workspace["name"]
        },
        "provider" => input["providerID"],
        "model" => input["model"],
        "estimatedCost" => input["estimatedCost"].to_f,
        "projectedDailySpend" => projected_daily_spend,
        "reasons" => reasons,
        "recommendation" => recommendation,
        "fallbackProvider" => fallback,
        "timestamp" => Time.now.utc.iso8601
      }
    }
  end

  def offline_workspace(config, workspace_id)
    workspace = config.fetch("workspace", {})
    budgets = config.fetch("budgets", {})
    providers = config.fetch("providers", {})
    models = config.fetch("models", {})

    {
      "id" => workspace["id"] || workspace_id,
      "name" => workspace["name"] || workspace["id"] || workspace_id,
      "pathHint" => workspace["path"] || workspace["pathHint"] || Dir.pwd,
      "client" => workspace["client"] || "local",
      "dailyBudget" => numeric_config(budgets["daily"], 0),
      "monthlyBudget" => numeric_config(budgets["monthly"], 0),
      "spendToday" => numeric_config(budgets["spend_today"] || budgets["spendToday"], 0),
      "spendMonth" => numeric_config(budgets["spend_month"] || budgets["spendMonth"], 0),
      "allowedProviderIDs" => Array(providers["allowed"]).map(&:to_s),
      "blockedModels" => Array(models["blocked"]).map(&:to_s),
      "maxEstimatedRunCost" => numeric_config(budgets["max_run"] || budgets["maxEstimatedRunCost"], Float::INFINITY),
      "requireCompanyKey" => providers["require_company_key"] == true || providers["requireCompanyKey"] == true
    }
  end

  def recommendation(status, model, fallback)
    case status
    when "allow"
      "Continue with #{model}. Keep the agent on this workspace policy."
    when "warn"
      "Continue only if this run is necessary, or switch to #{fallback || "a cheaper allowed provider"} first."
    else
      "Stop this run. Switch provider/model or raise the workspace budget after review."
    end
  end

  def config_summary(config)
    return nil unless config

    workspace = config.fetch("workspace", {})
    budgets = config.fetch("budgets", {})
    providers = config.fetch("providers", {})
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
      }
    }
  end

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
    puts
    puts "Smoke check: #{smoke["status"].to_s.upcase}"
    Array(smoke["reasons"]).each { |reason| puts "- #{reason}" }
    puts
    puts "Next: run tokenbar check --agent codex --provider #{load_config(payload["policy"]).dig("providers", "preferred")} --model #{default_model(load_config(payload["policy"]).dig("providers", "preferred"))}"
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

TokenBarCLI.main(ARGV)
