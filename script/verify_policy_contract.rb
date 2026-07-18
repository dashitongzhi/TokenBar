#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tempfile"
require "yaml"
require_relative "../lib/tokenbar_cli"

FIXTURE_PATH = File.expand_path("fixtures/policy_contract.json", __dir__)
CLI_PATH = File.expand_path("../lib/tokenbar_cli.rb", __dir__)

def deep_merge(base, override)
  return base unless override

  base.merge(override) do |_key, left, right|
    left.is_a?(Hash) && right.is_a?(Hash) ? deep_merge(left, right) : right
  end
end

def verify_decision!(case_id, decision, expected)
  failures = []
  failures << "status=#{decision["status"].inspect}, expected #{expected["status"].inspect}" unless decision["status"] == expected["status"]

  Array(expected["reasonsInclude"]).each do |reason|
    failures << "missing reason #{reason.inspect}" unless decision.fetch("reasons").include?(reason)
  end
  Array(expected["reasonsExclude"]).each do |reason|
    failures << "unexpected reason #{reason.inspect}" if decision.fetch("reasons").include?(reason)
  end
  %w[projectedDailySpend projectedMonthlySpend].each do |key|
    next unless expected.key?(key)

    failures << "#{key}=#{decision[key].inspect}, expected #{expected[key].inspect}" unless decision[key] == expected[key]
  end

  return if failures.empty?

  warn "Policy contract #{case_id.inspect} failed: #{failures.join("; ")}"
  exit 1
end

def run_cli_check(policy_path, key_source)
  Open3.capture3(
    RbConfig.ruby,
    CLI_PATH,
    "--api-url",
    "http://127.0.0.1:1",
    "--config",
    policy_path,
    "--json",
    "check",
    "--agent",
    "codex",
    "--provider",
    "openai",
    "--model",
    "gpt-5",
    "--estimated-cost",
    "1",
    "--estimated-tokens",
    "1000",
    "--key-source",
    key_source
  )
end

fixture = JSON.parse(File.read(FIXTURE_PATH))
defaults = fixture.fetch("defaults")
verified_cases = 0

fixture.fetch("cases").each do |contract_case|
  key_source = contract_case.dig("input", "keySource")
  variants = if key_source == "$companyManagedKeySource"
               fixture.fetch("companyManagedKeySources")
             else
               [key_source]
             end

  variants.each do |variant|
    input_override = contract_case.fetch("input", {}).dup
    input_override["keySource"] = variant if key_source == "$companyManagedKeySource"
    input = deep_merge(defaults.fetch("input"), input_override)
    config = deep_merge(defaults.fetch("config"), contract_case.fetch("config", {}))
    decision = TokenBarCLI.offline_policy_response(input, config).fetch("decision")
    suffix = key_source == "$companyManagedKeySource" ? ":#{variant}" : ""
    verify_decision!("#{contract_case.fetch("id")}#{suffix}", decision, contract_case.fetch("expected"))
    verified_cases += 1
  end
end

Tempfile.create(["tokenbar-policy-contract", ".yml"]) do |policy_file|
  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    CLI_PATH,
    "policy",
    "init",
    "--output",
    policy_file.path,
    "--force",
    "--workspace-id",
    "policy-contract-cli",
    "--workspace-name",
    "Policy Contract CLI",
    "--daily-budget",
    "0",
    "--monthly-budget",
    "0",
    "--max-run-cost",
    "0",
    "--allowed-providers",
    "openai",
    "--preferred-provider",
    "openai",
    "--default-model",
    "gpt-5",
    "--require-company-key",
    "--blocked-models",
    "",
    "--json"
  )
  unless status.success?
    warn "policy init zero-cap smoke failed: #{stderr.empty? ? stdout : stderr}"
    exit 1
  end

  generated = YAML.safe_load(File.read(policy_file.path))
  unless generated.dig("budgets", "max_run") == 0.0
    warn "policy init zero-cap smoke wrote unexpected max_run: #{generated.dig("budgets", "max_run").inspect}"
    exit 1
  end


  managed_stdout, managed_stderr, managed_status = run_cli_check(policy_file.path, "company")
  managed_response = JSON.parse(managed_stdout) if managed_status.success?
  unless managed_status.success? && managed_response.dig("decision", "status") == "allow" && managed_response["source"] == "tokenbar_yml"
    warn "managed-key CLI smoke failed: #{managed_stderr.empty? ? managed_stdout : managed_stderr}"
    exit 1
  end

  personal_stdout, personal_stderr, personal_status = run_cli_check(policy_file.path, "personal")
  personal_response = JSON.parse(personal_stdout) if personal_status.exitstatus == 2
  unless personal_status.exitstatus == 2 && personal_response.dig("decision", "status") == "block"
    warn "personal-key CLI smoke failed: #{personal_stderr.empty? ? personal_stdout : personal_stderr}"
    exit 1
  end
end

puts "Verified #{verified_cases} shared policy contract decisions, zero-cap policy init, and offline CLI exit codes."
