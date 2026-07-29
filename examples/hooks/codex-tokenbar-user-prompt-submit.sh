#!/usr/bin/env bash
set -u

INPUT="$(cat)"
ERROR_FILE="$(mktemp "${TMPDIR:-/tmp}/tokenbar-codex-hook.XXXXXX")"
trap 'rm -f "$ERROR_FILE"' EXIT

block_evaluation_failure() {
  local context="$1"
  ruby -rjson -e '
    puts JSON.generate({
      decision: "block",
      reason: "TokenBar BLOCK: policy evaluation failed; refusing to run without a verified policy decision.",
      hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: ARGV.fetch(0)
      }
    })
  ' "$context"
  exit 0
}

decision_matches() {
  local expected="$1"
  ruby -rjson -e '
    payload = JSON.parse(STDIN.read)
    decision = payload.fetch("decision")
    abort "unexpected decision" unless decision.fetch("status") == ARGV.fetch(0)
  ' "$expected" 2>/dev/null
}

TOKENBAR_BIN="${TOKENBAR_BIN:-tokenbar}"
PROVIDER="${TOKENBAR_PROVIDER:-}"
MODEL="${TOKENBAR_MODEL:-}"
INTENT="${TOKENBAR_INTENT:-codex_prompt}"
CHECK_ARGS=(
  check
  --agent codex
  --codex-hook-json
  --intent "$INTENT"
  --json
)

if [[ -n "$PROVIDER" ]]; then
  CHECK_ARGS+=(--provider "$PROVIDER")
fi

if [[ -n "$MODEL" ]]; then
  CHECK_ARGS+=(--model "$MODEL")
fi

if [[ -n "${TOKENBAR_KEY_SOURCE:-}" ]]; then
  CHECK_ARGS+=(--key-source "$TOKENBAR_KEY_SOURCE")
fi

if [[ -n "${TOKENBAR_ESTIMATED_COST:-}" ]]; then
  CHECK_ARGS+=(--estimated-cost "$TOKENBAR_ESTIMATED_COST")
fi

if [[ -n "${TOKENBAR_ESTIMATED_TOKENS:-}" ]]; then
  CHECK_ARGS+=(--estimated-tokens "$TOKENBAR_ESTIMATED_TOKENS")
fi

OUTPUT="$(printf "%s" "$INPUT" | "$TOKENBAR_BIN" "${CHECK_ARGS[@]}" 2>"$ERROR_FILE")"
STATUS=$?
ERROR_OUTPUT="$(cat "$ERROR_FILE")"

case "$STATUS" in
  0)
    printf "%s" "$OUTPUT" | decision_matches allow ||
      block_evaluation_failure "${ERROR_OUTPUT:-invalid ALLOW response from TokenBar}"
    exit 0
    ;;
  1)
    ruby -rjson -e '
      payload = JSON.parse(ARGV.fetch(0))
      decision = payload.fetch("decision")
      abort "unexpected decision" unless decision.fetch("status") == "warn"
      context = "TokenBar WARN: #{decision.fetch("recommendation")}"
      puts JSON.generate({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: context
        }
      })
    ' "$OUTPUT" 2>/dev/null || block_evaluation_failure "${ERROR_OUTPUT:-invalid WARN response from TokenBar}"
    exit 0
    ;;
  2)
    ruby -rjson -e '
      payload = JSON.parse(ARGV.fetch(0))
      decision = payload.fetch("decision")
      abort "unexpected decision" unless decision.fetch("status") == "block"
      reasons = Array(decision["reasons"]).join(" ")
      puts JSON.generate({
        decision: "block",
        reason: "TokenBar BLOCK: #{reasons} #{decision.fetch("recommendation")}"
      })
    ' "$OUTPUT" 2>/dev/null || block_evaluation_failure "${ERROR_OUTPUT:-invalid BLOCK response from TokenBar}"
    exit 0
    ;;
  *)
    block_evaluation_failure "${ERROR_OUTPUT:-$OUTPUT}"
    ;;
esac
