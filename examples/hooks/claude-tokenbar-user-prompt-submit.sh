#!/usr/bin/env bash
set -u

INPUT="$(cat)"
PROMPT="$(
  ruby -rjson -e 'payload = JSON.parse(ARGF.read) rescue {}; puts((payload["prompt"] || payload["user_prompt"] || payload["message"] || payload["input"]).to_s)' <<<"$INPUT"
)"

TOKENBAR_BIN="${TOKENBAR_BIN:-tokenbar}"
PROVIDER="${TOKENBAR_PROVIDER:-anthropic}"
MODEL="${TOKENBAR_MODEL:-claude-sonnet}"
ESTIMATED_TOKENS="${TOKENBAR_ESTIMATED_TOKENS:-}"
if [[ -z "$ESTIMATED_TOKENS" ]]; then
  ESTIMATED_TOKENS="$(ruby -e 'prompt = STDIN.read; prompt_tokens = (prompt.length / 4.0).ceil; puts [prompt_tokens + 4096, 8192].max' <<<"$PROMPT")"
fi

ESTIMATED_COST="${TOKENBAR_ESTIMATED_COST:-}"
if [[ -z "$ESTIMATED_COST" ]]; then
  ESTIMATED_COST="$(ruby -e 'model, tokens = ARGV; rate = model.downcase.include?("opus") ? 45.0 : (model.downcase.include?("haiku") ? 3.0 : 18.0); puts format("%.4f", tokens.to_f * rate / 1_000_000)' "$MODEL" "$ESTIMATED_TOKENS")"
fi
INTENT="${TOKENBAR_INTENT:-claude_prompt}"

OUTPUT="$("$TOKENBAR_BIN" check \
  --agent claudeCode \
  --provider "$PROVIDER" \
  --model "$MODEL" \
  --estimated-cost "$ESTIMATED_COST" \
  --estimated-tokens "$ESTIMATED_TOKENS" \
  --prompt "$PROMPT" \
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
    ruby -rjson -e 'puts JSON.generate({ decision: "block", reason: "TokenBar BLOCK: policy evaluation failed; refusing to run without a verified policy decision.", hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: ARGV.fetch(0) } })' "$OUTPUT"
    exit 0
    ;;
esac
