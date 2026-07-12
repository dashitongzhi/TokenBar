#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/TokenBar/Services/ProviderModelCatalogEndpointPolicy.swift" \
  "$ROOT_DIR/script/verify_provider_model_catalog_endpoint_policy.swift" \
  -o "$BUILD_DIR/verify_provider_model_catalog_endpoint_policy"

"$BUILD_DIR/verify_provider_model_catalog_endpoint_policy"
