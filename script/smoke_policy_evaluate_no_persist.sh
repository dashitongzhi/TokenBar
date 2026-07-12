#!/usr/bin/env bash
set -euo pipefail

API_URL="${TOKENBAR_API_URL:-http://127.0.0.1:3847}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/local_api_state.sh"
TOKEN_PATH="$(tokenbar_api_token_path)" || TOKEN_PATH=""
STATE_DIR="$(dirname "$TOKEN_PATH")"
POLICY_STORE="${TOKENBAR_WORKSPACE_POLICY_STORE:-$STATE_DIR/workspace-policies.json}"
WORKSPACE_ID="${TOKENBAR_POLICY_SMOKE_WORKSPACE_ID:-local-api-transient-regression}"

fail() {
  printf "error: %s\n" "$*" >&2
  exit 1
}

json_field() {
  local path="$1"
  ruby -rjson -e '
    value = JSON.parse(STDIN.read)
    ARGV.first.split(".").each { |key| value = value.fetch(key) }
    puts value
  ' "$path"
}

workspace_ids() {
  ruby -rjson -e '
    payload = JSON.parse(STDIN.read)
    puts Array(payload["workspaces"]).map { |workspace| workspace["id"].to_s }.sort
  '
}

workspace_store_contains_id() {
  local id="$1"
  [[ -f "$POLICY_STORE" ]] || return 1
  ruby -rjson -e '
    id = ARGV.fetch(0)
    data = JSON.parse(File.read(ARGV.fetch(1)))
    exit(Array(data).any? { |workspace| workspace["id"].to_s == id } ? 0 : 1)
  ' "$id" "$POLICY_STORE"
}

[[ -r "$TOKEN_PATH" ]] || fail "local API token is not readable at $TOKEN_PATH"
TOKEN="$(tr -d "[:space:]" < "$TOKEN_PATH")"
[[ -n "$TOKEN" ]] || fail "local API token is empty"

before_policy="$(curl -fsS --max-time 3 \
  -H "Authorization: Bearer $TOKEN" \
  "$API_URL/policy")" || fail "GET /policy failed"
before_workspace_ids="$(printf "%s" "$before_policy" | workspace_ids)"

payload="$(ruby -rjson -e '
  workspace_id = ARGV.fetch(0)
  puts JSON.generate({
    "agent" => "codex",
    "workspaceID" => workspace_id,
    "workspaceName" => "Transient Regression Workspace",
    "workspacePath" => "/tmp/tokenbar-transient-regression",
    "workspaceClient" => "local",
    "providerID" => "anthropic",
    "model" => "claude-sonnet",
    "estimatedCost" => 0.01,
    "estimatedTokens" => 1000,
    "intent" => "regression-smoke",
    "allowedProviderIDs" => ["openai"],
    "blockedModels" => [],
    "maxEstimatedRunCost" => 1.0,
    "requireCompanyKey" => false,
    "preferredProviderID" => "openai",
    "preferredModel" => "gpt-5"
  })
' "$WORKSPACE_ID")"

decision="$(curl -fsS --max-time 3 \
  -X POST "$API_URL/policy/evaluate" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data "$payload")" || fail "POST /policy/evaluate failed"

status="$(printf "%s" "$decision" | json_field "decision.status")"
decision_workspace_id="$(printf "%s" "$decision" | json_field "decision.workspace.id")"
[[ "$status" == "block" ]] || fail "expected transient policy to block anthropic, got status=$status"
[[ "$decision_workspace_id" == "$WORKSPACE_ID" ]] || fail "expected decision workspace $WORKSPACE_ID, got $decision_workspace_id"

after_policy="$(curl -fsS --max-time 3 \
  -H "Authorization: Bearer $TOKEN" \
  "$API_URL/policy")" || fail "GET /policy after evaluation failed"
after_workspace_ids="$(printf "%s" "$after_policy" | workspace_ids)"

[[ "$after_workspace_ids" == "$before_workspace_ids" ]] || fail "/policy workspace list changed after transient evaluation"

if printf "%s" "$after_policy" | workspace_ids | grep -Fxq "$WORKSPACE_ID"; then
  fail "transient workspace appeared in /policy workspace list"
fi

if workspace_store_contains_id "$WORKSPACE_ID"; then
  fail "transient workspace was persisted to $POLICY_STORE"
fi

printf "Verified /policy/evaluate transient policy: decision=%s workspace=%s persisted=false\n" "$status" "$WORKSPACE_ID"
