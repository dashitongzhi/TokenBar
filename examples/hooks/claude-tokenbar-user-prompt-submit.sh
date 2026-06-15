#!/usr/bin/env bash
set -u

INPUT="$(cat)"
PROMPT="$(
  ruby -rjson -e 'payload = JSON.parse(ARGF.read) rescue {}; puts(payload["prompt"].to_s)' <<<"$INPUT"
)"

TOKENBAR_BIN="${TOKENBAR_BIN:-tokenbar}"
PROVIDER="${TOKENBAR_PROVIDER:-anthropic}"
MODEL="${TOKENBAR_MODEL:-claude-sonnet}"
ESTIMATED_COST="${TOKENBAR_ESTIMATED_COST:-0}"
ESTIMATED_TOKENS="${TOKENBAR_ESTIMATED_TOKENS:-0}"
INTENT="${TOKENBAR_INTENT:-claude_prompt}"

OUTPUT="$("$TOKENBAR_BIN" check \
  --agent claudeCode \
  --provider "$PROVIDER" \
  --model "$MODEL" \
  --estimated-cost "$ESTIMATED_COST" \
  --estimated-tokens "$ESTIMATED_TOKENS" \
  --intent "$INTENT" \
  --json 2>&1)"
STATUS=$?

case "$STATUS" in
  0)
    exit 0
    ;;
  1)
    ruby -rjson -e '
      payload = JSON.parse(ARGV.fetch(0))
      decision = payload.fetch("decision")
      puts JSON.generate({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: "TokenBar WARN: #{decision.fetch("recommendation")}"
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
        reason: "TokenBar BLOCK: #{reasons} #{decision.fetch("recommendation")}",
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: "TokenBar evaluated this prompt before Claude Code processed it."
        }
      })
    ' "$OUTPUT"
    exit 0
    ;;
  *)
    ruby -rjson -e 'puts JSON.generate({ hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: "TokenBar hook could not evaluate policy: #{ARGV.fetch(0)}" } })' "$OUTPUT"
    exit 0
    ;;
esac
