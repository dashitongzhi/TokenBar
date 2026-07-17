#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

SOURCES=(
  "$ROOT_DIR/TokenBar/Services/LocalAPIHTTP.swift"
  "$ROOT_DIR/TokenBar/Services/LocalAPIApplication.swift"
  "$ROOT_DIR/script/verify_local_api_application.swift"
)
swiftc "${SOURCES[@]}" -o "$BUILD_DIR/verify_local_api_application"

"$BUILD_DIR/verify_local_api_application"
