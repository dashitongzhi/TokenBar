#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

SOURCES=(
  "$ROOT_DIR/TokenBar/App/JSONDocumentStore.swift"
  "$ROOT_DIR/script/verify_json_document_store.swift"
)
swiftc "${SOURCES[@]}" -o "$BUILD_DIR/verify_json_document_store"

"$BUILD_DIR/verify_json_document_store"
