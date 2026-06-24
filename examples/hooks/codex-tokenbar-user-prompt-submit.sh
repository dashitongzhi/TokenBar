#!/usr/bin/env bash
set -u

INPUT="$(cat)"

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

OUTPUT="$(printf "%s" "$INPUT" | "$TOKENBAR_BIN" "${CHECK_ARGS[@]}" 2>&1)"
STATUS=$?

case "$STATUS" in
  0)
    exit 0
    ;;
  1)
    ruby -rjson -e '
      payload = JSON.parse(ARGV.fetch(0))
      decision = payload.fetch("decision")
      context = "TokenBar WARN: #{decision.fetch("recommendation")}"
      puts JSON.generate({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: context
        }
      })
    ' "$OUTPUT"
    exit 0
    ;;
  2)
    ruby -rjson -e '
      payload = JSON.parse(ARGV.fetch(0))
      decision = payload.fetch("decision")
      reasons = Array(decision["reasons"]).join(" ")
      puts JSON.generate({
        decision: "block",
        reason: "TokenBar BLOCK: #{reasons} #{decision.fetch("recommendation")}"
      })
    ' "$OUTPUT"
    exit 0
    ;;
  *)
    ruby -rjson -e 'puts JSON.generate({ systemMessage: "TokenBar hook could not evaluate policy: #{ARGV.fetch(0)}" })' "$OUTPUT"
    exit 0
    ;;
esac
