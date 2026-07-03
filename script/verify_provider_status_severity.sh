#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/TokenBar/Core/Models.swift" \
  "$ROOT_DIR/TokenBar/Core/ModelPresentation.swift" \
  "$ROOT_DIR/script/verify_provider_status_severity.swift" \
  -o "$BUILD_DIR/verify_provider_status_severity"

"$BUILD_DIR/verify_provider_status_severity"
