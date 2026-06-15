#!/usr/bin/env bash
set -u

INPUT="$(cat)"
MODEL="$(
  ruby -rjson -e 'payload = JSON.parse(ARGF.read) rescue {}; puts(payload["model"].to_s)' <<<"$INPUT"
)"
PROMPT="$(
  ruby -rjson -e 'payload = JSON.parse(ARGF.read) rescue {}; puts(payload["prompt"].to_s)' <<<"$INPUT"
)"

TOKENBAR_BIN="${TOKENBAR_BIN:-tokenbar}"
PROVIDER="${TOKENBAR_PROVIDER:-openai}"
MODEL="${TOKENBAR_MODEL:-${MODEL:-gpt-5}}"
ESTIMATED_COST="${TOKENBAR_ESTIMATED_COST:-0}"
ESTIMATED_TOKENS="${TOKENBAR_ESTIMATED_TOKENS:-0}"
INTENT="${TOKENBAR_INTENT:-codex_prompt}"

OUTPUT="$("$TOKENBAR_BIN" check \
  --agent codex \
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
