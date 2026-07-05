#!/usr/bin/env bash
set -euo pipefail

API_URL="${TOKENBAR_API_URL:-http://127.0.0.1:3847}"
TOKEN_PATH="${TOKENBAR_API_TOKEN_PATH:-$HOME/Library/Application Support/TokenBar/local-api-token}"
LEDGER_PATH="$HOME/Library/Application Support/TokenBar/smart-routing-runs.json"

ROUTING_LEDGER_BACKUP_PATH=""
ROUTING_LEDGER_EXISTED=0

fail() {
  printf "error: %s\n" "$*" >&2
  exit 1
}

restore_routing_ledger() {
  [[ -n "$ROUTING_LEDGER_BACKUP_PATH" ]] || return 0

  if [[ "$ROUTING_LEDGER_EXISTED" == "1" ]]; then
    mkdir -p "$(dirname "$LEDGER_PATH")"
    cp "$ROUTING_LEDGER_BACKUP_PATH" "$LEDGER_PATH"
  else
    rm -f "$LEDGER_PATH"
  fi

  rm -f "$ROUTING_LEDGER_BACKUP_PATH"
  ROUTING_LEDGER_BACKUP_PATH=""
  ROUTING_LEDGER_EXISTED=0
}

write_routing_fixture() {
  local fixture_id="$1"

  mkdir -p "$(dirname "$LEDGER_PATH")"
  ruby -rjson -rtime -e '
    fixture_id = ARGV.fetch(0)

    def record(fixture_id, index, task_intent:, provider_id:, model:, workspace_id:, session_id:, selected_by:, metadata: {})
      now = Time.now.utc.iso8601
      {
        "id" => "00000000-0000-4000-8000-%012d" % index,
        "recordedAt" => now,
        "occurredAt" => now,
        "agent" => "codex",
        "taskIntent" => task_intent,
        "providerID" => provider_id,
        "model" => model,
        "workspaceID" => workspace_id,
        "workspaceName" => "Local API stats fixture",
        "workspacePath" => "/tmp/#{fixture_id}",
        "sessionID" => session_id,
        "taskID" => "#{fixture_id}-task-#{index}",
        "estimatedCost" => 0.2,
        "actualCost" => 0.18,
        "estimatedTokens" => 1000,
        "actualTokens" => 900,
        "inputTokens" => 600,
        "outputTokens" => 300,
        "requestCount" => 1,
        "signal" => "success",
        "followUpRequired" => false,
        "selectedBy" => selected_by,
        "alternatives" => [],
        "routingReason" => "Local API routing stats fixture",
        "metadata" => metadata
      }
    end

    records = [
      record(
        fixture_id,
        1,
        task_intent: "production-recommendation-#{fixture_id}",
        provider_id: "openai",
        model: "gpt-5-production-#{fixture_id}",
        workspace_id: "workspace-#{fixture_id}",
        session_id: "session-production-#{fixture_id}",
        selected_by: "policy",
        metadata: { "purpose" => "local-api-contract" }
      ),
      record(
        fixture_id,
        2,
        task_intent: "smoke",
        provider_id: "openai",
        model: "gpt-5-smoke-#{fixture_id}",
        workspace_id: "workspace-#{fixture_id}",
        session_id: "session-smoke-#{fixture_id}",
        selected_by: "policy"
      ),
      record(
        fixture_id,
        3,
        task_intent: "production-recommendation-#{fixture_id}",
        provider_id: "openai",
        model: "gpt-5-selected-by-test-#{fixture_id}",
        workspace_id: "workspace-#{fixture_id}",
        session_id: "session-selected-by-test-#{fixture_id}",
        selected_by: "test"
      ),
      record(
        fixture_id,
        4,
        task_intent: "production-recommendation-#{fixture_id}",
        provider_id: "anthropic",
        model: "claude-opus-synthetic-#{fixture_id}",
        workspace_id: "workspace-#{fixture_id}",
        session_id: "session-metadata-synthetic-#{fixture_id}",
        selected_by: "policy",
        metadata: { "synthetic" => "true" }
      ),
      record(
        fixture_id,
        5,
        task_intent: "production-recommendation-#{fixture_id}",
        provider_id: "anthropic",
        model: "claude-opus-unknown-cost",
        workspace_id: "smoke-routing-ledger",
        session_id: "session-unknown-cost-#{fixture_id}",
        selected_by: "policy"
      )
    ]

    File.write(ARGV.fetch(1), JSON.pretty_generate(records))
  ' "$fixture_id" "$LEDGER_PATH"
}

assert_routing_stats() {
  local fixture_id="$1"
  local routing_stats

  routing_stats="$(curl -fsS --max-time 3 \
    -H "Authorization: Bearer $TOKEN" \
    "$API_URL/routing/stats")" || fail "GET /routing/stats failed"

  printf "%s" "$routing_stats" | ruby -rjson -e '
    fixture_id = ARGV.fetch(0)
    payload = JSON.parse(STDIN.read)
    stats = payload.fetch("stats")
    routes = payload.fetch("routes")
    recent_runs = payload.fetch("recentRuns")

    expected_task = "production-recommendation-#{fixture_id}"
    expected_model = "gpt-5-production-#{fixture_id}"

    excluded = stats.fetch("excludedNonProductionRuns")
    abort "stats.excludedNonProductionRuns must be numeric" unless excluded.is_a?(Numeric)
    abort "expected 4 excluded non-production runs, got #{excluded}" unless excluded == 4
    abort "expected exactly 1 production total run, got #{stats.fetch("totalRuns")}" unless stats.fetch("totalRuns") == 1
    abort "expected exactly 1 production win, got #{stats.fetch("winCount")}" unless stats.fetch("winCount") == 1

    production_route = routes.find { |route| route["taskIntent"] == expected_task && route["model"] == expected_model }
    abort "production route was not surfaced in /routing/stats routes" unless production_route
    abort "production route runCount must be 1" unless production_route["runCount"] == 1

    leaked_models = routes.map { |route| route["model"].to_s }.grep(/smoke|selected-by-test|synthetic|unknown-cost/)
    abort "non-production route leaked into production stats: #{leaked_models.join(", ")}" unless leaked_models.empty?

    abort "recentRuns should include only production recommendations" unless recent_runs.length == 1
    abort "recentRuns did not surface the production fixture" unless recent_runs.fetch(0).fetch("model") == expected_model
  ' "$fixture_id" || fail "/routing/stats did not exclude smoke/test/synthetic recommendation runs"
}

[[ -r "$TOKEN_PATH" ]] || fail "local API token is not readable at $TOKEN_PATH"
TOKEN="$(tr -d "[:space:]" < "$TOKEN_PATH")"
[[ -n "$TOKEN" ]] || fail "local API token is empty"

ROUTING_LEDGER_BACKUP_PATH="$(mktemp)"
if [[ -f "$LEDGER_PATH" ]]; then
  cp "$LEDGER_PATH" "$ROUTING_LEDGER_BACKUP_PATH"
  ROUTING_LEDGER_EXISTED=1
fi
trap restore_routing_ledger EXIT

FIXTURE_ID="local-api-routing-stats-$(date +%s)-$$"
write_routing_fixture "$FIXTURE_ID"
assert_routing_stats "$FIXTURE_ID"
restore_routing_ledger
trap - EXIT

printf "Verified /routing/stats excludes smoke/test/synthetic runs and reports excludedNonProductionRuns\n"
