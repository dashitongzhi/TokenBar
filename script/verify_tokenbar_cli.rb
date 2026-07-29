#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "shellwords"
require "tempfile"
require "yaml"
require_relative "../lib/tokenbar_cli"

CLI_PATH = File.expand_path("../lib/tokenbar_cli.rb", __dir__)

def expect(condition, message)
  raise message unless condition
end

TokenBarCLI::ProviderCatalog::DEFAULT_MODELS.each do |provider, model|
  inferred = TokenBarCLI::ProviderCatalog.provider_for(hint: provider, model: model)
  expect(inferred == provider, "provider catalog drift for #{provider}/#{model}: #{inferred.inspect}")
  expect(TokenBarCLI.default_model(provider) == model, "default model drift for #{provider}")
end

expect(TokenBarCLI::Coercion.numeric(nil, 0) == 0, "numeric nil fallback changed")
expect(TokenBarCLI::Coercion.numeric("1.25", 0) == 1.25, "numeric coercion changed")
expect(TokenBarCLI::Coercion.integer("bad", 7) == 7, "integer invalid fallback changed")
expect(TokenBarCLI::Coercion.blank?(" \n"), "blank coercion changed")

compacted = TokenBarCLI.compact_hash(
  "workspaceID" => "cli-contract",
  "model" => nil,
  "nested" => { "keep" => 1, "drop" => nil },
  "array" => [1, nil, 2]
)
expect(
  compacted == {
    "workspaceID" => "cli-contract",
    "nested" => { "keep" => 1 },
    "array" => [1, 2]
  },
  "policy payload compaction changed: #{compacted.inspect}"
)

unsafe_root = Pathname.new("/tmp/token bar$(must-not-run)")
_path, hook_json = TokenBarCLI.hook_file("codex", Pathname.new("/tmp/workspace"), unsafe_root)
command = JSON.parse(hook_json).dig("hooks", "UserPromptSubmit", 0, "hooks", 0, "command")
tokens = Shellwords.split(command)
expect(tokens.fetch(0) == "TOKENBAR_BIN=#{unsafe_root.join("bin/tokenbar")}", "TOKENBAR_BIN shell quoting changed")
expect(tokens.fetch(1) == unsafe_root.join("examples/hooks/codex-tokenbar-user-prompt-submit.sh").to_s, "hook path shell quoting changed")

_stdout, stderr, status = Open3.capture3(
  RbConfig.ruby,
  CLI_PATH,
  "status",
  "--api-url",
  "127.0.0.1:3847",
  "--json"
)
expect(status.exitstatus == 3, "unexpected exception must use exit code 3, got #{status.exitstatus}")
expect(stderr.include?("absolute http:// or https://"), "invalid URL error was not actionable: #{stderr.inspect}")

Tempfile.create(["tokenbar-cli-options", ".yml"]) do |file|
  file.write(
    YAML.dump(
      "version" => 1,
      "workspace" => { "id" => "cli-options", "name" => "CLI Options" },
      "budgets" => { "daily" => 0, "monthly" => 0 },
      "providers" => { "allowed" => ["openai"], "preferred" => "openai" },
      "models" => { "default" => "gpt-5", "blocked" => [] }
    )
  )
  file.flush

  common = [
    "--api-url", "http://127.0.0.1:1",
    "--json",
    "check",
    "--agent", "codex",
    "--provider", "openai",
    "--model", "gpt-5",
    "--estimated-cost", "0",
    "--estimated-tokens", "0"
  ]
  before_stdout, before_stderr, before_status = Open3.capture3(
    RbConfig.ruby,
    CLI_PATH,
    "--config",
    file.path,
    *common
  )
  after_stdout, after_stderr, after_status = Open3.capture3(
    RbConfig.ruby,
    CLI_PATH,
    *common,
    "--config",
    file.path
  )
  expect(before_status.exitstatus == 0, "global option before command failed: #{before_stderr}")
  expect(after_status.exitstatus == 0, "global option after command failed: #{after_stderr}")
  expect(JSON.parse(before_stdout).dig("decision", "status") == "allow", "before-command decision changed")
  expect(JSON.parse(after_stdout).dig("decision", "status") == "allow", "after-command decision changed")
end

puts "Verified TokenBar CLI provider, coercion, payload, URL, shell quoting, error-code, and global-option contracts."
