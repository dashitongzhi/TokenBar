#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/TokenBar/App/MiniMaxQuotaAuditSemantics.swift" \
  "$ROOT_DIR/script/verify_minimax_ccswitch_fallback_audit.swift" \
  -o "$BUILD_DIR/verify_minimax_ccswitch_fallback_audit"

"$BUILD_DIR/verify_minimax_ccswitch_fallback_audit"
