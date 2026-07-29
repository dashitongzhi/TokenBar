#!/usr/bin/env bash
set -u

INPUT="$(cat)"
ERROR_FILE="$(mktemp "${TMPDIR:-/tmp}/tokenbar-claude-hook.XXXXXX")"
trap 'rm -f "$ERROR_FILE"' EXIT

block_invalid_input() {
  local reason="$1"
  ruby -rjson -e '
    puts JSON.generate({
      decision: "block",
      reason: "TokenBar BLOCK: #{ARGV.fetch(0)}",
      hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: "TokenBar refused to evaluate an invalid Claude hook payload."
      }
    })
  ' "$reason"
  exit 0
}

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

if ! PROMPT="$(ruby -rjson -e '
  payload = JSON.parse(STDIN.read)
  prompt = payload["prompt"] || payload["user_prompt"] || payload["message"] || payload["input"]
  raise KeyError, "missing prompt" if prompt.nil?
  raise TypeError, "prompt must be a string" unless prompt.is_a?(String)
  raise KeyError, "empty prompt" if prompt.strip.empty?
  print prompt
' <<<"$INPUT" 2>/dev/null)"; then
  block_invalid_input "invalid hook JSON; refusing to run without a verified prompt."
fi
[[ -n "$PROMPT" ]] || block_invalid_input "hook payload has no prompt; refusing to run without a verified prompt."

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

OUTPUT="$(printf "%s" "$PROMPT" | "$TOKENBAR_BIN" check \
  --agent claudeCode \
  --provider "$PROVIDER" \
  --model "$MODEL" \
  --estimated-cost "$ESTIMATED_COST" \
  --estimated-tokens "$ESTIMATED_TOKENS" \
  --prompt-stdin \
  --intent "$INTENT" \
  --json 2>"$ERROR_FILE")"
STATUS=$?
ERROR_OUTPUT="$(cat "$ERROR_FILE")"

case "$STATUS" in
  0)
    printf "%s" "$OUTPUT" | decision_matches allow ||
      block_evaluation_failure "${ERROR_OUTPUT:-invalid ALLOW response from TokenBar}"
    exit 0
    ;;
  1)
    if ! printf "%s" "$OUTPUT" | ruby -rjson -e '
      payload = JSON.parse(ARGV.fetch(0))
      decision = payload.fetch("decision")
      abort "unexpected decision" unless decision.fetch("status") == "warn"
      puts JSON.generate({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: "TokenBar WARN: #{decision.fetch("recommendation")}"
        }
      })
    ' "$OUTPUT" 2>/dev/null; then
      block_evaluation_failure "${ERROR_OUTPUT:-invalid WARN response from TokenBar}"
    fi
    exit 0
    ;;
  2)
    if ! ruby -rjson -e '
      payload = JSON.parse(ARGV.fetch(0))
      decision = payload.fetch("decision")
      abort "unexpected decision" unless decision.fetch("status") == "block"
      reasons = Array(decision["reasons"]).join(" ")
      puts JSON.generate({
        decision: "block",
        reason: "TokenBar BLOCK: #{reasons} #{decision.fetch("recommendation")}",
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: "TokenBar evaluated this prompt before Claude Code processed it."
        }
      })
    ' "$OUTPUT" 2>/dev/null; then
      block_evaluation_failure "${ERROR_OUTPUT:-invalid BLOCK response from TokenBar}"
    fi
    exit 0
    ;;
  *)
    block_evaluation_failure "${ERROR_OUTPUT:-$OUTPUT}"
    ;;
esac
