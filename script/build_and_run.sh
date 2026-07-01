#!/bin/bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="TokenBar"
SCHEME="TokenBar"
PROJECT="TokenBar.xcodeproj"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
BUNDLE_ID="Kral.TokenBar"
APP_PORT="3847"
HEALTH_URL="http://127.0.0.1:$APP_PORT/health"
VERIFY_TIMEOUT="${TOKENBAR_VERIFY_TIMEOUT:-20}"
LOCAL_API_PREF_KEY="localAPIEnabled"
LOCAL_API_PREF_CAPTURED="0"
LOCAL_API_PREF_WAS_SET="0"
LOCAL_API_PREF_VALUE=""
LOCAL_API_PREF_REQUIRES_APP_STOP="0"
VERIFY_APP_PID=""
VERIFY_EXEC="$ROOT_DIR/.build/tokenbar-verify/$APP_NAME"
VERIFY_ENTITLEMENTS="$ROOT_DIR/.build/tokenbar-verify.entitlements"
VERIFY_STDOUT="$ROOT_DIR/.build/tokenbar-verify.stdout.log"
VERIFY_STDERR="$ROOT_DIR/.build/tokenbar-verify.stderr.log"

if [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

cd "$ROOT_DIR"

stage() {
  printf "\n==> %s\n" "$*"
}

fail() {
  printf "error: %s\n" "$*" >&2
  exit 1
}

app_pids() {
  pgrep -x "$APP_NAME" 2>/dev/null || true
  if [[ -n "$VERIFY_APP_PID" ]] && kill -0 "$VERIFY_APP_PID" >/dev/null 2>&1; then
    printf "%s\n" "$VERIFY_APP_PID"
  fi
}

latest_app_pid() {
  app_pids | tail -n 1
}

wait_for_app_exit() {
  local deadline=$((SECONDS + 5))
  while [[ -n "$(app_pids)" && $SECONDS -lt $deadline ]]; do
    sleep 0.2
  done
  [[ -z "$(app_pids)" ]] || fail "existing $APP_NAME process did not exit"
}

process_state() {
  local pid="$1"
  local stat
  stat="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d "[:space:]")"
  if [[ -z "$stat" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    stat="alive"
  fi
  printf "%s\n" "$stat"
}

process_is_stopped() {
  local stat="$1"
  [[ "$stat" == *T* ]]
}

process_is_launched_suspended() {
  local pid="$1"
  vmmap "$pid" 2>/dev/null | grep -q "launched-suspended"
}

pid_has_local_api_listener() {
  local pid="$1"
  local listeners
  listeners="$(lsof -nP -a -p "$pid" -iTCP:"$APP_PORT" -sTCP:LISTEN 2>/dev/null)" || return 1
  grep -qE "TCP (127\\.0\\.0\\.1|\\*):$APP_PORT .*\\(LISTEN\\)" <<<"$listeners"
}

health_check_ok() {
  local body
  body="$(curl -fsS --max-time 2 "$HEALTH_URL" 2>/dev/null)" || return 1
  [[ "$body" == *'"status":"ok"'* && "$body" == *'"service":"TokenBar"'* ]]
}

capture_local_api_preference() {
  local value
  LOCAL_API_PREF_CAPTURED="1"
  if value="$(defaults read "$BUNDLE_ID" "$LOCAL_API_PREF_KEY" 2>/dev/null)"; then
    LOCAL_API_PREF_WAS_SET="1"
    LOCAL_API_PREF_VALUE="$value"
  else
    LOCAL_API_PREF_WAS_SET="0"
    LOCAL_API_PREF_VALUE=""
  fi
}

restore_local_api_preference() {
  [[ "$LOCAL_API_PREF_CAPTURED" == "1" ]] || return 0

  if [[ "$LOCAL_API_PREF_WAS_SET" == "1" ]]; then
    if [[ "$LOCAL_API_PREF_VALUE" == "1" || "$LOCAL_API_PREF_VALUE" == "true" || "$LOCAL_API_PREF_VALUE" == "TRUE" ]]; then
      defaults write "$BUNDLE_ID" "$LOCAL_API_PREF_KEY" -bool true
    else
      defaults write "$BUNDLE_ID" "$LOCAL_API_PREF_KEY" -bool false
      LOCAL_API_PREF_REQUIRES_APP_STOP="1"
    fi
  else
    defaults delete "$BUNDLE_ID" "$LOCAL_API_PREF_KEY" >/dev/null 2>&1 || true
  fi

  if [[ "$LOCAL_API_PREF_REQUIRES_APP_STOP" == "1" ]]; then
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  fi
}

stop_verify_process() {
  [[ -n "$VERIFY_APP_PID" ]] || return 0
  if kill -0 "$VERIFY_APP_PID" >/dev/null 2>&1; then
    kill "$VERIFY_APP_PID" >/dev/null 2>&1 || true
    local deadline=$((SECONDS + 5))
    while kill -0 "$VERIFY_APP_PID" >/dev/null 2>&1 && [[ $SECONDS -lt $deadline ]]; do
      sleep 0.2
    done
    kill -9 "$VERIFY_APP_PID" >/dev/null 2>&1 || true
  fi
  wait "$VERIFY_APP_PID" >/dev/null 2>&1 || true
}

cleanup_verify() {
  local status=$?
  stop_verify_process
  restore_local_api_preference
  exit "$status"
}

enable_local_api_for_verify() {
  capture_local_api_preference
  trap cleanup_verify EXIT INT TERM
  stage "Enabling local API preference for verification"
  defaults write "$BUNDLE_ID" "$LOCAL_API_PREF_KEY" -bool true
}

verify_app() {
  [[ "$VERIFY_TIMEOUT" =~ ^[0-9]+$ && "$VERIFY_TIMEOUT" -gt 0 ]] || fail "TOKENBAR_VERIFY_TIMEOUT must be a positive integer"

  stage "Verifying process, local API listener, and health endpoint (timeout ${VERIFY_TIMEOUT}s)"
  local deadline=$((SECONDS + VERIFY_TIMEOUT))
  local last_status="waiting for $APP_NAME to launch"

  while [[ $SECONDS -lt $deadline ]]; do
    local pid
    pid="$(latest_app_pid)"
    if [[ -z "$pid" ]]; then
      last_status="$APP_NAME process is not running"
      sleep 1
      continue
    fi

    local stat
    stat="$(process_state "$pid")"
    if [[ -z "$stat" ]]; then
      last_status="$APP_NAME process $pid disappeared"
      sleep 1
      continue
    fi

    if process_is_stopped "$stat"; then
      last_status="$APP_NAME process $pid is stopped or suspended (stat=$stat)"
      sleep 1
      continue
    fi

    if process_is_launched_suspended "$pid"; then
      last_status="$APP_NAME process $pid exists but has not started (launched-suspended)"
      sleep 1
      continue
    fi

    if ! pid_has_local_api_listener "$pid"; then
      last_status="$APP_NAME process $pid is running (stat=$stat), but is not listening on TCP $APP_PORT"
      sleep 1
      continue
    fi

    if ! health_check_ok; then
      last_status="$HEALTH_URL did not return the expected TokenBar health payload"
      sleep 1
      continue
    fi

    printf "Verified %s pid=%s stat=%s local_api=%s\n" "$APP_NAME" "$pid" "$stat" "$HEALTH_URL"
    return 0
  done

  printf "Verification failed after %ss: %s\n" "$VERIFY_TIMEOUT" "$last_status" >&2
  printf "\nProcess state:\n" >&2
  ps -axo pid,stat,comm | grep -E "^[[:space:]]*[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+.*$APP_NAME$" >&2 || true
  printf "\nPort %s listeners:\n" "$APP_PORT" >&2
  lsof -nP -iTCP:"$APP_PORT" -sTCP:LISTEN >&2 || true
  printf "\nHealth probe:\n" >&2
  curl -i --max-time 2 "$HEALTH_URL" >&2 || true
  if [[ -s "$VERIFY_STDOUT" || -s "$VERIFY_STDERR" ]]; then
    printf "\nVerification process output:\n" >&2
    sed -n '1,120p' "$VERIFY_STDOUT" >&2 2>/dev/null || true
    sed -n '1,120p' "$VERIFY_STDERR" >&2 2>/dev/null || true
  fi
  return 1
}

stage "Stopping existing $APP_NAME processes"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
wait_for_app_exit

stage "Building $SCHEME Debug"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  ENABLE_DEBUG_DYLIB=NO \
  CODE_SIGNING_ALLOWED="${TOKENBAR_CODE_SIGNING_ALLOWED:-NO}" \
  build

open_app() {
  stage "Launching $APP_NAME"
  /usr/bin/open -n "$APP_BUNDLE"
}

open_verify_app() {
  stage "Preparing local API verifier executable"
  mkdir -p "$(dirname "$VERIFY_EXEC")"
  rm -f "$VERIFY_EXEC"
  cp "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$VERIFY_EXEC"
  chmod +x "$VERIFY_EXEC"
  cat > "$VERIFY_ENTITLEMENTS" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.network.server</key>
  <true/>
</dict>
</plist>
ENTITLEMENTS
  codesign --force --sign - --entitlements "$VERIFY_ENTITLEMENTS" "$VERIFY_EXEC" >/dev/null 2>&1 || fail "failed to ad-hoc sign verifier executable"

  stage "Launching $APP_NAME local API verification mode"
  : > "$VERIFY_STDOUT"
  : > "$VERIFY_STDERR"
  "$VERIFY_EXEC" --tokenbar-verify-local-api >"$VERIFY_STDOUT" 2>"$VERIFY_STDERR" &
  VERIFY_APP_PID="$!"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    enable_local_api_for_verify
    open_verify_app
    verify_app
    stage "Running local API transient policy smoke"
    "$ROOT_DIR/script/smoke_policy_evaluate_no_persist.sh"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
