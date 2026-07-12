#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/tokenbar_cli"

input = {
  "agent" => "codex",
  "workspaceID" => "offline-budget-smoke",
  "providerID" => "openai",
  "model" => "gpt-5",
  "estimatedCost" => 2.0,
  "estimatedTokens" => 0,
  "intent" => "offline-budget-smoke"
}
config = {
  "workspace" => { "id" => "offline-budget-smoke", "name" => "Offline Budget Smoke" },
  "budgets" => { "daily" => 100, "monthly" => 20, "spend_today" => 1, "spend_month" => 19, "max_run" => 100 },
  "providers" => { "allowed" => ["openai"] },
  "models" => { "blocked" => [] }
}

decision = TokenBarCLI.offline_policy_response(input, config).fetch("decision")
unless decision.fetch("status") == "block" &&
       decision.fetch("projectedMonthlySpend") == 21.0 &&
       decision.fetch("reasons").include?("Projected monthly spend would exceed the workspace budget.")
  warn "Offline monthly policy regression: #{decision.inspect}"
  exit 1
end

puts "Verified offline CLI monthly workspace budget enforcement."
