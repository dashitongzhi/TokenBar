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
  LOCAL_API_TOKEN_PATH = Pathname.new("~/Library/Application Support/TokenBar/local-api-token").expand_path.freeze
  CONFIG_NAMES = %w[tokenbar.yml tokenbar.yaml].freeze
  EXIT_BY_STATUS = { "allow" => 0, "warn" => 1, "block" => 2 }.freeze
  AGENT_DISPLAY = {
    "claudeCode" => "Claude Code",
    "codex" => "Codex",
    "cursor" => "Cursor",
    "continueDev" => "Continue",
    "custom" => "Custom Agent"
  }.freeze
  DEFAULT_CODEX_PRICING = [
    [/gpt-5\.5|gpt-5/i, { input: 1.25, cached_input: 0.125, output: 10.00 }],
    [/gpt-4\.1/i, { input: 2.00, cached_input: 0.50, output: 8.00 }],
    [/o4-mini|o3-mini/i, { input: 1.10, cached_input: 0.275, output: 4.40 }],
    [/o3/i, { input: 10.00, cached_input: 2.50, output: 40.00 }]
  ].freeze
  CODEX_PROMPT_TOKEN_DIVISOR = 4.0
  CODEX_TASK_SIZE_ESTIMATES = {
    small: { base_input: 8_000, output: 2_000 },
    medium: { base_input: 24_000, output: 6_000 },
    large: { base_input: 60_000, output: 14_000 },
    xlarge: { base_input: 120_000, output: 28_000 }
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
      opts.banner = "Usage: tokenbar [--api-url URL] [--config PATH] <status|check|policy|usage> [options]"
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
    raise Error, "missing command: use status, check, policy, or usage" unless command

    case command
    when "status"
      status(options, argv)
    when "check"
      check(options, argv)
    when "policy"
      policy(options, argv)
    when "usage"
      usage(options, argv)
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

  def post_json(api_url, path, input)
    uri = endpoint(api_url, path)
    if curl_available?
      body = curl_request(["-X", "POST", "-H", "Content-Type: application/json", *auth_curl_headers, "--data", JSON.generate(input), uri.to_s])
      return body ? JSON.parse(body) : nil
    end

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    apply_auth_header(request)
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
      body = curl_request([*auth_curl_headers, uri.to_s])
      return body ? JSON.parse(body) : nil
    end

    request = Net::HTTP::Get.new(uri)
    apply_auth_header(request)
    response = http_request(uri, request)
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
    @last_api_error = nil
    stdout, _stderr, status = Open3.capture3("curl", "-sS", "--max-time", "2", "-w", "\n%{http_code}", *args)
    unless status.success?
      @last_api_error = "connection_failed"
      return nil
    end

    body, separator, code = stdout.rpartition("\n")
    unless separator && code.match?(/\A\d{3}\z/)
      @last_api_error = "invalid_response"
      return nil
    end

    http_status = code.to_i
    return body if http_status.between?(200, 299)

    @last_api_error = "http_#{http_status}"
    nil
  end

  def http_request(uri, request)
    @last_api_error = nil
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 0.5, read_timeout: 1.5) do |http|
      response = http.request(request)
      @last_api_error = "http_#{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response
    end
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError, Net::OpenTimeout, Net::ReadTimeout
    @last_api_error = "connection_failed"
    nil
  end

  def auth_curl_headers
    token = api_token
    return [] if blank?(token)

    ["-H", "Authorization: Bearer #{token}"]
  end

  def apply_auth_header(request)
    token = api_token
    request["Authorization"] = "Bearer #{token}" unless blank?(token)
  end

  def api_token
    env_token = ENV["TOKENBAR_API_TOKEN"]
    return env_token.strip unless blank?(env_token)
    return nil unless LOCAL_API_TOKEN_PATH.file?

    LOCAL_API_TOKEN_PATH.read.strip
  rescue SystemCallError
    nil
  end

  def api_failure_message(action)
    case @last_api_error
    when "http_401"
      "TokenBar local API rejected the request; set TOKENBAR_API_TOKEN or start the current TokenBar app so #{LOCAL_API_TOKEN_PATH} is available"
    when "http_403"
      "TokenBar local API rejected the request origin or authorization; #{action}"
    when "http_400"
      "TokenBar local API rejected the payload; #{action}"
    when "http_404", "http_405"
      "TokenBar local API route or method is not supported by the running app; #{action}"
    when /\Ahttp_(\d{3})\z/
      "TokenBar local API returned HTTP #{Regexp.last_match(1)}; #{action}"
    else
      "TokenBar app is not running; #{action}"
    end
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
    input["allowedProviderIDs"] = workspace["allowedProviderIDs"]
    input["blockedModels"] = workspace["blockedModels"]
    input["requireCompanyKey"] = workspace["requireCompanyKey"]
    input["providerID"] ||= config.dig("providers", "preferred") || workspace["allowedProviderIDs"].first
    input
  end

  def validate_usage_input!(input)
    valid_agents = AGENT_DISPLAY.keys
    raise Error, "--agent must be one of #{valid_agents.join(", ")}" unless valid_agents.include?(input["agent"])
    raise Error, "missing provider: pass --provider or set providers.preferred in tokenbar.yml" if blank?(input["providerID"])
    raise Error, "missing model: pass --model or set TOKENBAR_MODEL" if blank?(input["model"])
    raise Error, "--cost-usd must be >= 0" if input["costUSD"].to_f.negative?
    raise Error, "token counts must be >= 0" if %w[inputTokens outputTokens totalTokens requestCount].any? { |key| !input[key].nil? && input[key].to_i.negative? }
  end

  def provider_from_model_or_agent(model, agent)
    model = model.to_s.downcase
    return "anthropic" if model.include?("claude")
    return "openai" if model.include?("gpt") || model.match?(/\bo[34]\b/)
    return "anthropic" if agent == "claudeCode"
    return "openai" if agent == "codex"

    nil
  end

  def claude_statusline_usage_input(payload)
    input_tokens = integer_deep_find(payload, %w[input_tokens inputTokens])
    output_tokens = integer_deep_find(payload, %w[output_tokens outputTokens])
    cache_creation_tokens = integer_deep_find(payload, %w[cache_creation_input_tokens cacheCreationInputTokens]).to_i
    cache_read_tokens = integer_deep_find(payload, %w[cache_read_input_tokens cacheReadInputTokens]).to_i
    explicit_total = integer_deep_find(payload, %w[total_tokens totalTokens tokens_used tokensUsed])
    computed_total = [input_tokens, output_tokens].compact.sum + cache_creation_tokens + cache_read_tokens
    current_directory = dig_path(payload, %w[workspace current_dir]) ||
                        dig_path(payload, %w[workspace currentDirectory]) ||
                        string_deep_find(payload, %w[current_dir currentDirectory cwd])
    {
      "agent" => "claudeCode",
      "providerID" => "anthropic",
      "model" => dig_path(payload, %w[model id]) || dig_path(payload, %w[model name]) || string_deep_find(payload, %w[model_id modelId]),
      "sessionID" => string_deep_find(payload, %w[session_id sessionId]),
      "source" => "Claude Code statusline",
      "currentDirectory" => current_directory,
      "workspacePath" => current_directory,
      "transcriptPath" => string_deep_find(payload, %w[transcript_path transcriptPath]),
      "costUSD" => numeric_deep_find(payload, %w[total_cost_usd totalCostUSD cost_usd costUSD]),
      "inputTokens" => input_tokens,
      "outputTokens" => output_tokens,
      "totalTokens" => explicit_total || (computed_total.positive? ? computed_total : nil),
      "contextWindowSize" => integer_deep_find(payload, %w[context_window_size contextWindowSize]),
      "requestCount" => integer_deep_find(payload, %w[request_count requestCount]),
      "occurredAt" => iso8601_deep_find(payload, %w[timestamp occurred_at occurredAt]),
      "rateLimitUsedPercentage" => numeric_deep_find(payload, %w[used_percentage usedPercentage rate_limit_used_percentage rateLimitUsedPercentage]),
      "rateLimitResetAt" => iso8601_deep_find(payload, %w[reset_at resetAt rate_limit_reset_at rateLimitResetAt]),
      "cumulative" => true
    }
  end

  def codex_session_usage_input(hook_payload, options, config)
    transcript_path = options[:transcript] ||
                      string_deep_find(hook_payload, %w[transcript_path transcriptPath transcript_file transcriptFile transcript])
    transcript = codex_transcript_summary(transcript_path)
    model = options[:model] ||
            string_deep_find(hook_payload, %w[model model_id modelId]) ||
            transcript["model"] ||
            "gpt-5"
    usage = transcript.fetch("usage", {})
    input_tokens = usage["input_tokens"].to_i
    cached_input_tokens = usage["cached_input_tokens"].to_i
    output_tokens = usage["output_tokens"].to_i
    total_tokens = usage["total_tokens"].to_i
    total_tokens = input_tokens + output_tokens if total_tokens.zero? && (input_tokens + output_tokens).positive?
    pricing = codex_pricing_for(model, config)
    cost = numeric_deep_find(hook_payload, %w[cost_usd costUSD total_cost_usd totalCostUSD]) ||
           numeric_env("TOKENBAR_CODEX_COST_USD", nil) ||
           estimate_codex_cost(usage, pricing)
    cwd = options[:cwd] ||
          string_deep_find(hook_payload, %w[cwd current_dir currentDirectory]) ||
          transcript["cwd"] ||
          Dir.pwd
    session_id = options[:session_id] ||
                 string_deep_find(hook_payload, %w[session_id sessionId]) ||
                 transcript["sessionID"] ||
                 (transcript_path ? File.basename(transcript_path, ".jsonl") : nil)

    {
      "agent" => "codex",
      "providerID" => "openai",
      "model" => model,
      "sessionID" => session_id,
      "source" => "Codex local transcript",
      "currentDirectory" => cwd,
      "workspacePath" => cwd,
      "transcriptPath" => transcript_path,
      "costUSD" => cost,
      "inputTokens" => input_tokens,
      "outputTokens" => output_tokens,
      "totalTokens" => total_tokens,
      "contextWindowSize" => transcript["contextWindowSize"],
      "requestCount" => transcript["requestCount"],
      "occurredAt" => transcript["occurredAt"] || Time.now.utc.iso8601,
      "cumulative" => true
    }
  end

  def apply_codex_prompt_payload!(input, options, payload)
    return if payload.empty?

    input["agent"] = "codex" if input["agent"] == "custom"
    input["model"] ||= dig_path(payload, %w[model id]) ||
                       dig_path(payload, %w[model name]) ||
                       string_deep_find(payload, %w[model model_id modelId])
    input["intent"] = string_deep_find(payload, %w[intent task_kind taskKind]) || input["intent"]
    input["keySource"] ||= string_deep_find(payload, %w[key_source keySource key_provenance keyProvenance])
    options[:prompt] ||= string_deep_find(payload, %w[prompt user_prompt userPrompt message input])
    options[:cwd] ||= string_deep_find(payload, %w[cwd current_dir currentDirectory workspace_path workspacePath])
  end

  def apply_codex_key_source_default!(input, options)
    return unless input["agent"] == "codex"
    return unless blank?(input["keySource"])

    input["keySource"] = if options[:codex_hook_json]
                           "codex_managed"
                         elsif input["providerID"] == "openai" && openai_key_env_present?
                           "env"
                         end
  end

  def openai_key_env_present?
    %w[OPENAI_API_KEY TOKENBAR_OPENAI_API_KEY OPENAI_KEY TOKENBAR_OPENAI_KEY].any? { |name| !blank?(ENV[name]) }
  end

  def apply_codex_preflight_estimate!(input, options, config)
    return nil unless input["agent"] == "codex"
    return nil if options[:cost_explicit] && options[:tokens_explicit]

    prompt = codex_preflight_prompt(options)
    return nil if blank?(prompt)

    model = input["model"] || default_model("openai")
    pricing = codex_pricing_for(model, config)
    estimate = estimate_codex_prompt_run(prompt, model, pricing, config)
    input["estimatedTokens"] = estimate["estimatedTokens"] unless options[:tokens_explicit]
    input["estimatedCost"] = estimate["estimatedCost"] unless options[:cost_explicit]
    estimate
  end

  def codex_preflight_prompt(options)
    return options[:prompt] unless blank?(options[:prompt])
    return nil if blank?(options[:prompt_file])

    Pathname.new(options[:prompt_file]).expand_path.read
  rescue SystemCallError => e
    raise Error, "could not read --prompt-file #{options[:prompt_file]}: #{e.message}"
  end

  def estimate_codex_prompt_run(prompt, model, pricing, config)
    prompt_tokens = approximate_token_count(prompt)
    size = codex_prompt_task_size(prompt, prompt_tokens, config)
    size_estimate = CODEX_TASK_SIZE_ESTIMATES.fetch(size)
    input_tokens = prompt_tokens + size_estimate[:base_input]
    output_tokens = size_estimate[:output]
    usage = {
      "input_tokens" => input_tokens,
      "cached_input_tokens" => 0,
      "output_tokens" => output_tokens,
      "total_tokens" => input_tokens + output_tokens
    }
    cost = estimate_codex_cost(usage, pricing)

    {
      "source" => "codex_prompt_heuristic",
      "model" => model,
      "taskSize" => size.to_s,
      "promptTokens" => prompt_tokens,
      "estimatedInputTokens" => input_tokens,
      "estimatedOutputTokens" => output_tokens,
      "estimatedTokens" => usage["total_tokens"],
      "estimatedCost" => cost.round(6),
      "pricingUSDPer1M" => {
        "input" => pricing[:input].to_f,
        "cachedInput" => pricing[:cached_input].to_f,
        "output" => pricing[:output].to_f
      }
    }
  end

  def approximate_token_count(text)
    normalized = text.to_s.gsub(/\s+/, " ").strip
    return 0 if normalized.empty?

    char_estimate = (normalized.length / CODEX_PROMPT_TOKEN_DIVISOR).ceil
    word_estimate = (normalized.scan(/[[:alnum:]_]+/).length * 1.3).ceil
    [char_estimate, word_estimate, 1].max
  end

  def codex_prompt_task_size(prompt, prompt_tokens, config)
    configured = config&.dig("codex", "preflight_size") || config&.dig("codex", "preflightSize")
    return configured.to_s.downcase.to_sym if CODEX_TASK_SIZE_ESTIMATES.key?(configured.to_s.downcase.to_sym)

    text = prompt.to_s.downcase
    return :xlarge if prompt_tokens >= 8_000 || text.match?(/\b(rewrite|rebuild|migrate|redesign|audit all|entire repo|full app|large refactor)\b/)
    return :large if prompt_tokens >= 2_000 || text.match?(/\b(implement|refactor|verify|test|debug|fix|wire|integrate|frontend|ui|deploy|docs|examples)\b/)
    return :small if prompt_tokens <= 80 && text.match?(/\b(explain|summarize|rename|format|translate|what is|show me)\b/)

    :medium
  end

  def codex_transcript_summary(path)
    raise Error, "missing Codex transcript path; pass --transcript or run from a Codex Stop hook" if blank?(path)

    expanded = Pathname.new(path).expand_path
    raise Error, "Codex transcript not found: #{expanded}" unless expanded.file?

    summary = { "usage" => {}, "requestCount" => 0, "transcriptPath" => expanded.to_s }
    File.foreach(expanded) do |line|
      entry = JSON.parse(line)
      payload = entry["payload"] || {}
      case entry["type"]
      when "session_meta"
        summary["sessionID"] ||= payload["id"]
        summary["cwd"] ||= payload["cwd"]
      when "turn_context"
        summary["cwd"] = payload["cwd"] if payload["cwd"]
        summary["model"] = payload["model"] if payload["model"]
      when "event_msg"
        next unless payload["type"] == "token_count"

        info = payload["info"] || {}
        usage = info["total_token_usage"] || {}
        summary["usage"] = normalize_codex_token_usage(usage)
        summary["contextWindowSize"] = info["model_context_window"]
        summary["occurredAt"] = entry["timestamp"]
        summary["requestCount"] += 1
      end
    rescue JSON::ParserError
      next
    end
    raise Error, "Codex transcript has no token_count events: #{expanded}" if summary["usage"].empty?

    summary
  end

  def normalize_codex_token_usage(usage)
    {
      "input_tokens" => usage["input_tokens"].to_i,
      "cached_input_tokens" => usage["cached_input_tokens"].to_i,
      "output_tokens" => usage["output_tokens"].to_i,
      "reasoning_output_tokens" => usage["reasoning_output_tokens"].to_i,
      "total_tokens" => usage["total_tokens"].to_i
    }
  end

  def codex_pricing_for(model, config)
    config_rate = codex_config_pricing(model, config)
    env_rate = {
      input: numeric_env("TOKENBAR_CODEX_INPUT_USD_PER_1M", nil),
      cached_input: numeric_env("TOKENBAR_CODEX_CACHED_INPUT_USD_PER_1M", nil),
      output: numeric_env("TOKENBAR_CODEX_OUTPUT_USD_PER_1M", nil)
    }.compact
    return config_rate.merge(env_rate) if config_rate
    return (DEFAULT_CODEX_PRICING.find { |pattern, _rate| model.to_s.match?(pattern) }&.last || {}).merge(env_rate) if env_rate.empty? == false

    DEFAULT_CODEX_PRICING.find { |pattern, _rate| model.to_s.match?(pattern) }&.last ||
      { input: 0.0, cached_input: 0.0, output: 0.0 }
  end

  def codex_config_pricing(model, config)
    pricing = config&.dig("codex", "pricing") || config&.dig("pricing", "codex")
    return nil unless pricing.is_a?(Hash)

    raw = pricing[model.to_s] || pricing[model.to_s.downcase] || pricing["default"]
    return nil unless raw.is_a?(Hash)

    {
      input: numeric_config(raw["input_per_million"] || raw["inputPerMillion"], 0),
      cached_input: numeric_config(raw["cached_input_per_million"] || raw["cachedInputPerMillion"], 0),
      output: numeric_config(raw["output_per_million"] || raw["outputPerMillion"], 0)
    }
  end

  def estimate_codex_cost(usage, pricing)
    input_tokens = usage["input_tokens"].to_i
    cached_input_tokens = [usage["cached_input_tokens"].to_i, input_tokens].min
    uncached_input_tokens = [input_tokens - cached_input_tokens, 0].max
    output_tokens = usage["output_tokens"].to_i

    (uncached_input_tokens * pricing[:input].to_f +
      cached_input_tokens * pricing[:cached_input].to_f +
      output_tokens * pricing[:output].to_f) / 1_000_000.0
  end

  def read_stdin_json
    return {} if STDIN.tty?

    raw = STDIN.read
    return {} if blank?(raw)

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

  def dig_path(value, keys)
    cursor = value
    keys.each do |key|
      return nil unless cursor.is_a?(Hash)

      cursor = cursor[key]
    end
    cursor.is_a?(String) && !cursor.empty? ? cursor : nil
  end

  def string_deep_find(value, keys)
    found = deep_find(value, keys)
    return nil if found.nil?
    return nil if found.is_a?(Hash) || found.is_a?(Array)

    found.to_s.empty? ? nil : found.to_s
  end

  def numeric_deep_find(value, keys)
    found = deep_find(value, keys)
    return nil if found.nil?

    Float(found)
  rescue ArgumentError, TypeError
    nil
  end

  def integer_deep_find(value, keys)
    found = numeric_deep_find(value, keys)
    found.nil? ? nil : found.to_i
  end

  def iso8601_deep_find(value, keys)
    found = deep_find(value, keys)
    return nil if found.nil?
    return Time.at(found).utc.iso8601 if found.is_a?(Numeric)

    string = found.to_s
    return Time.at(Float(string)).utc.iso8601 if string.match?(/\A\d+(\.\d+)?\z/)

    Time.parse(string).utc.iso8601
  rescue ArgumentError
    nil
  end

  def deep_find(value, keys)
    if value.is_a?(Hash)
      keys.each { |key| return value[key] if value.key?(key) }
      value.each_value do |child|
        found = deep_find(child, keys)
        return found unless found.nil?
      end
    elsif value.is_a?(Array)
      value.each do |child|
        found = deep_find(child, keys)
        return found unless found.nil?
      end
    end
    nil
  end

  def compact_hash(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, item), memo|
        compacted = compact_hash(item)
        memo[key] = compacted unless compacted.nil?
      end
    when Array
      value.map { |item| compact_hash(item) }.compact
    else
      value
    end
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

    if workspace["requireCompanyKey"] && company_key_required_but_unsatisfied?(input)
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
        "keySource" => input["keySource"],
        "estimatedCost" => input["estimatedCost"].to_f,
        "projectedDailySpend" => projected_daily_spend,
        "reasons" => reasons,
        "recommendation" => recommendation,
        "fallbackProvider" => fallback,
        "timestamp" => Time.now.utc.iso8601
      }
    }
  end

  def company_key_required_but_unsatisfied?(input)
    return false unless input["providerID"] == "openai"

    !company_managed_key_source?(input["keySource"])
  end

  def company_managed_key_source?(source)
    normalized = source.to_s.downcase.tr("-", "_")
    %w[company company_managed managed codex_managed tokenbar_keychain tokenbar api_proxy org workspace].include?(normalized)
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

  def format_money(value)
    format("%.2f", value)
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
