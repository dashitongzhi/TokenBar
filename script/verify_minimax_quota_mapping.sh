#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/TokenBar/Services/CCSwitchLiveQuotaModels.swift" \
  "$ROOT_DIR/script/verify_minimax_quota_mapping.swift" \
  -o "$BUILD_DIR/verify_minimax_quota_mapping"

"$BUILD_DIR/verify_minimax_quota_mapping"
