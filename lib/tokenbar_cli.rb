#!/usr/bin/ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "optparse"
require "pathname"
require "time"
require "yaml"
require_relative "tokenbar_cli/local_api_client"
require_relative "tokenbar_cli/offline_policy"
require_relative "tokenbar_cli/policy_configuration"
require_relative "tokenbar_cli/agent_usage"
require_relative "tokenbar_cli/presentation"

module TokenBarCLI
  extend Presentation

  DEFAULT_API_URL = "http://127.0.0.1:3847"
  LOCAL_API_TOKEN_PATHS = [
    Pathname.new("~/Library/Containers/Kral.TokenBar/Data/Library/Application Support/TokenBar/local-api-token").expand_path,
    Pathname.new("~/Library/Application Support/TokenBar/local-api-token").expand_path
  ].freeze
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
      opts.banner = "Usage: tokenbar [--api-url URL] [--config PATH] <status|check|policy|usage|routing> [options]"
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
    raise Error, "missing command: use status, check, policy, usage, or routing" unless command

    case command
    when "status"
      status(options, argv)
    when "check"
      check(options, argv)
    when "policy"
      policy(options, argv)
    when "usage"
      usage(options, argv)
    when "routing"
      routing(options, argv)
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
    attach_config_policy!(input, config)
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
    inferred = infer_workspace_policy(cwd)
    init_options = {
      output: cwd.join("tokenbar.yml"),
      workspace_id: slug(cwd.basename.to_s),
      workspace_name: titleize(cwd.basename.to_s),
      workspace_path: cwd.to_s,
      client: "local",
      daily_budget: 8.00,
      monthly_budget: 160.00,
      max_run: inferred[:max_run],
      max_estimated_tokens: 0,
      spend_today: 0.00,
      spend_month: 0.00,
      allowed_providers: inferred[:allowed_providers],
      preferred_provider: inferred[:preferred_provider],
      default_model: inferred[:default_model],
      require_company_key: false,
      blocked_models: inferred[:blocked_models],
      inference: inferred,
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
      opts.on("--max-run-cost USD", Float, "Per-run cost cap in USD; 0 disables the cap (default: inferred from local agent config)") { |value| init_options[:max_run] = value }
      opts.on("--max-estimated-tokens TOKENS", Integer, "Block a run above this estimated token count (0 disables the cap)") { |value| init_options[:max_estimated_tokens] = value }
      opts.on("--allowed-providers LIST", "Comma-separated providers (default: inferred from local agent config)") { |value| init_options[:allowed_providers] = split_list(value) }
      opts.on("--preferred-provider PROVIDER", "Preferred provider (default: inferred from local agent config)") { |value| init_options[:preferred_provider] = value }
      opts.on("--default-model MODEL", "Default model written to models.default (default: inferred from local agent config)") { |value| init_options[:default_model] = value }
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
      "model" => init_options[:default_model],
      "estimatedCost" => 0.0,
      "estimatedTokens" => 0,
      "intent" => "policy_init_smoke"
    }
    decision = offline_policy_response(sample_input, config).fetch("decision")

    payload = {
      "policy" => init_options[:output].to_s,
      "hooks" => init_options[:hooks],
      "written" => written,
      "inference" => inferred,
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

TokenBarCLI.main(ARGV) if $PROGRAM_NAME == __FILE__
