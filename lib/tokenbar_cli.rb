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
require_relative "tokenbar_cli/agent_usage"
require_relative "tokenbar_cli/presentation"
require_relative "tokenbar_cli/config_discovery"
require_relative "tokenbar_cli/policy_scaffolding"
require_relative "tokenbar_cli/policy_configuration"
require_relative "tokenbar_cli/command_support"
require_relative "tokenbar_cli/commands/status_check"
require_relative "tokenbar_cli/commands/policy"
require_relative "tokenbar_cli/commands/usage"
require_relative "tokenbar_cli/commands/routing"

module TokenBarCLI
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

  extend Presentation
  extend ConfigDiscovery
  extend PolicyScaffolding
  extend PolicyConfiguration
  extend CommandSupport
  extend Commands::StatusCheck
  extend Commands::Policy
  extend Commands::Usage
  extend Commands::Routing

  def self.main(argv)
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
end

TokenBarCLI.main(ARGV) if $PROGRAM_NAME == __FILE__
