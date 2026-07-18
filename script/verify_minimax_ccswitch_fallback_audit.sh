#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

if [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

swiftc \
  "$ROOT_DIR/TokenBar/App/MiniMaxQuotaAuditSemantics.swift" \
  "$ROOT_DIR/script/verify_minimax_ccswitch_fallback_audit.swift" \
  -o "$BUILD_DIR/verify_minimax_ccswitch_fallback_audit"

"$BUILD_DIR/verify_minimax_ccswitch_fallback_audit"

DERIVED_DATA="$ROOT_DIR/.build/xcode"
APP_EXEC="$DERIVED_DATA/Build/Products/Debug/TokenBar.app/Contents/MacOS/TokenBar"

xcodebuild \
  -project "$ROOT_DIR/TokenBar.xcodeproj" \
  -scheme TokenBar \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  ENABLE_DEBUG_DYLIB=NO \
  CODE_SIGNING_ALLOWED="${TOKENBAR_CODE_SIGNING_ALLOWED:-NO}" \
  build

"$APP_EXEC" --tokenbar-verify-minimax-ccswitch-fallback-audit
