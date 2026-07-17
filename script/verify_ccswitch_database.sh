#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

SOURCES=(
  "$ROOT_DIR/TokenBar/Services/CCSwitchDatabase.swift"
  "$ROOT_DIR/script/verify_ccswitch_database.swift"
)
swiftc "${SOURCES[@]}" -lsqlite3 -o "$BUILD_DIR/verify_ccswitch_database"

"$BUILD_DIR/verify_ccswitch_database"
