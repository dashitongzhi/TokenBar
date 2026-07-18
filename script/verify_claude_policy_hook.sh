#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT_DIR/examples/hooks/claude-tokenbar-user-prompt-submit.sh"

verify_blocked_payload() {
  local input="$1"
  local output
  output="$(printf '%s' "$input" | TOKENBAR_BIN=/usr/bin/false bash "$HOOK")"
  ruby -rjson -e '
    payload = JSON.parse(ARGV.fetch(0))
    abort "invalid hook payload must block" unless payload["decision"] == "block"
    abort "block reason must explain invalid input" unless payload["reason"].to_s.include?("refusing to run")
  ' "$output"
}

verify_blocked_payload '{not-json'
verify_blocked_payload '{}'
verify_blocked_payload '{"prompt":{}}'
verify_blocked_payload '{"prompt":[]}'
verify_blocked_payload '{"prompt":123}'
verify_blocked_payload '{"prompt":true}'
verify_blocked_payload '{"prompt":"   "}'

valid_output="$(printf '%s' '{"prompt":"verify policy hook"}' | TOKENBAR_BIN=/usr/bin/true bash "$HOOK")"
[[ -z "$valid_output" ]] || {
  printf 'error: allow path should not emit a hook decision\n' >&2
  exit 1
}

printf 'Verified Claude UserPromptSubmit hook fails closed on invalid input.\n'
