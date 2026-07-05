#!/usr/bin/env bash
set -euo pipefail

API_URL="${TOKENBAR_API_URL:-http://127.0.0.1:3847}"
TOKEN_PATH="${TOKENBAR_API_TOKEN_PATH:-$HOME/Library/Application Support/TokenBar/local-api-token}"
PROVIDER_ID="${TOKENBAR_LOCAL_API_SMOKE_PROVIDER:-openai}"

fail() {
  printf "error: %s\n" "$*" >&2
  exit 1
}

json_contract() {
  ruby -rjson -e "$1" "$PROVIDER_ID"
}

[[ -r "$TOKEN_PATH" ]] || fail "local API token is not readable at $TOKEN_PATH"
TOKEN="$(tr -d "[:space:]" < "$TOKEN_PATH")"
[[ -n "$TOKEN" ]] || fail "local API token is empty"

routing_stats="$(curl -fsS --max-time 3 \
  -H "Authorization: Bearer $TOKEN" \
  "$API_URL/routing/stats")" || fail "GET /routing/stats failed"

printf "%s" "$routing_stats" | json_contract '
  payload = JSON.parse(STDIN.read)
  stats = payload.fetch("stats")
  value = stats.fetch("excludedNonProductionRuns")
  abort "stats.excludedNonProductionRuns must be numeric" unless value.is_a?(Numeric)
' || fail "/routing/stats did not include numeric stats.excludedNonProductionRuns"

quota_payload="$(curl -fsS --max-time 3 \
  -H "Authorization: Bearer $TOKEN" \
  "$API_URL/quotas/$PROVIDER_ID")" || fail "GET /quotas/$PROVIDER_ID failed"

printf "%s" "$quota_payload" | json_contract '
  provider_id = ARGV.fetch(0)
  payload = JSON.parse(STDIN.read)
  quota = Array(payload.fetch("quotas")).find { |entry| entry["platform"].to_s == provider_id }
  abort "provider quota not found for #{provider_id}" unless quota
  abort "quota.status is missing" unless quota.key?("status") && quota["status"].is_a?(String) && !quota["status"].empty?
  abort "quota.healthAlerts is missing or not an array" unless quota.key?("healthAlerts") && quota["healthAlerts"].is_a?(Array)
' || fail "/quotas/$PROVIDER_ID did not include status and healthAlerts"

printf "Verified authenticated local API contract: /routing/stats excludedNonProductionRuns and /quotas/%s status healthAlerts\n" "$PROVIDER_ID"
