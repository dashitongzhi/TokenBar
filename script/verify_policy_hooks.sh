#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_HOOK="$ROOT_DIR/examples/hooks/claude-tokenbar-user-prompt-submit.sh"
CODEX_HOOK="$ROOT_DIR/examples/hooks/codex-tokenbar-user-prompt-submit.sh"
STUB="$(mktemp "${TMPDIR:-/tmp}/tokenbar-hook-stub.XXXXXX")"
trap 'rm -f "$STUB"' EXIT

cat > "$STUB" <<'STUB'
#!/usr/bin/env bash
set -u
stdin="$(cat)"
for argument in "$@"; do
  if [[ -n "${STUB_SECRET_PROMPT:-}" && "$argument" == *"$STUB_SECRET_PROMPT"* ]]; then
    printf 'prompt leaked through argv\n' >&2
    exit 91
  fi
done
if [[ -n "${STUB_SECRET_PROMPT:-}" && "$stdin" != "$STUB_SECRET_PROMPT" ]]; then
  printf 'prompt was not provided on stdin\n' >&2
  exit 92
fi
printf '%s' "${STUB_STDERR:-}" >&2
if [[ "${STUB_OUTPUT:-json}" == "json" ]]; then
  ruby -rjson -e '
    status = ENV.fetch("STUB_DECISION", "allow")
    puts JSON.generate({
      decision: {
        status: status,
        recommendation: "stub recommendation",
        reasons: ["stub reason"]
      }
    })
  '
else
  printf '{broken-json'
fi
exit "${STUB_STATUS:-0}"
STUB
chmod 700 "$STUB"

assert_block() {
  ruby -rjson -e '
    payload = JSON.parse(STDIN.read)
    abort "expected decision:block, got #{payload.inspect}" unless payload["decision"] == "block"
  '
}

assert_warn() {
  ruby -rjson -e '
    payload = JSON.parse(STDIN.read)
    abort "warn must not block" if payload.key?("decision")
    context = payload.dig("hookSpecificOutput", "additionalContext").to_s
    abort "missing WARN context" unless context.include?("TokenBar WARN")
  '
}

run_case() {
  local hook="$1"
  local input="$2"
  local status="$3"
  local decision="$4"
  local output_mode="${5:-json}"
  local stderr_text="${6:-}"
  STUB_STATUS="$status" \
    STUB_DECISION="$decision" \
    STUB_OUTPUT="$output_mode" \
    STUB_STDERR="$stderr_text" \
    TOKENBAR_BIN="$STUB" \
    bash "$hook" <<<"$input"
}

secret_prompt='private prompt $(must-not-run)'
allow_output="$(
  STUB_SECRET_PROMPT="$secret_prompt" \
    STUB_STATUS=0 \
    STUB_DECISION=allow \
    TOKENBAR_BIN="$STUB" \
    bash "$CLAUDE_HOOK" <<<"{\"prompt\":\"$secret_prompt\"}"
)"
[[ -z "$allow_output" ]] || {
  printf 'error: verified ALLOW path should emit no hook decision\n' >&2
  exit 1
}

for invalid in '{not-json' '{}' '{"prompt":{}}' '{"prompt":[]}' '{"prompt":123}' '{"prompt":true}' '{"prompt":"   "}'; do
  run_case "$CLAUDE_HOOK" "$invalid" 0 allow | assert_block
done

for hook_and_input in \
  "$CLAUDE_HOOK|{\"prompt\":\"verify policy hook\"}" \
  "$CODEX_HOOK|{\"prompt\":\"verify policy hook\"}"; do
  hook="${hook_and_input%%|*}"
  input="${hook_and_input#*|}"

  allow_output="$(run_case "$hook" "$input" 0 allow)"
  [[ -z "$allow_output" ]] || {
    printf 'error: ALLOW path emitted output for %s\n' "$hook" >&2
    exit 1
  }
  run_case "$hook" "$input" 1 warn json 'stderr warning must stay separate' | assert_warn
  run_case "$hook" "$input" 2 block json 'stderr warning must stay separate' | assert_block
  run_case "$hook" "$input" 2 block invalid | assert_block
  run_case "$hook" "$input" 0 allow invalid | assert_block
  run_case "$hook" "$input" 127 block invalid 'CLI unavailable' | assert_block
done

printf 'Verified Claude and Codex policy hooks keep prompts off argv and fail closed on invalid or failed policy evaluation.\n'
