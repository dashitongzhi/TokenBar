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
  ps -o stat= -p "$pid" 2>/dev/null | tr -d "[:space:]"
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
  lsof -nP -a -p "$pid" -iTCP:"$APP_PORT" -sTCP:LISTEN >/dev/null 2>&1
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

enable_local_api_for_verify() {
  capture_local_api_preference
  trap restore_local_api_preference EXIT
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
  build

open_app() {
  stage "Launching $APP_NAME"
  /usr/bin/open -n "$APP_BUNDLE"
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
    open_app
    verify_app
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
