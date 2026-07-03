#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

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
