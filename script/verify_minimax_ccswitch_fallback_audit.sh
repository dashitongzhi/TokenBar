#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

if [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

SEMANTICS_SOURCE="$BUILD_DIR/MiniMaxQuotaAuditSemantics.swift"

if [[ -e "$ROOT_DIR/TokenBar/App/MiniMaxQuotaAuditSemantics.swift" ]]; then
  echo "MiniMaxQuotaAuditSemantics must live in AppState.swift to avoid target-membership ambiguity." >&2
  exit 1
fi

awk '
  /enum MiniMaxQuotaAuditSemantics/ {
    capture = 1
  }
  capture {
    print
    opens = gsub(/\{/, "{")
    closes = gsub(/\}/, "}")
    depth += opens - closes
    if (depth == 0) {
      exit
    }
  }
' "$ROOT_DIR/TokenBar/App/AppState.swift" > "$SEMANTICS_SOURCE"

if ! grep -q "MiniMaxQuotaAuditSemantics" "$SEMANTICS_SOURCE"; then
  echo "Could not extract MiniMaxQuotaAuditSemantics from AppState.swift." >&2
  exit 1
fi

swiftc \
  "$SEMANTICS_SOURCE" \
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
