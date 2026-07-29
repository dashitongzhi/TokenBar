#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/TokenBar/App/AppPreferencesStore.swift" \
  "$ROOT_DIR/script/verify_app_preferences_migration.swift" \
  -o "$BUILD_DIR/verify_app_preferences_migration"

"$BUILD_DIR/verify_app_preferences_migration"
