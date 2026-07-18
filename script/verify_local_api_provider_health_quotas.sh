#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/TokenBar/Core/AppPresentationModels.swift" \
  "$ROOT_DIR/TokenBar/Core/ProviderUsageModels.swift" \
  "$ROOT_DIR/TokenBar/Core/LocalUsageModels.swift" \
  "$ROOT_DIR/TokenBar/Core/SmartRoutingModels.swift" \
  "$ROOT_DIR/TokenBar/Core/WorkspacePolicyModels.swift" \
  "$ROOT_DIR"/TokenBar/App/LocalAPIWire*Models.swift \
  "$ROOT_DIR/TokenBar/App/LocalAPIPayloadBuilder.swift" \
  "$ROOT_DIR/script/verify_local_api_provider_health_quotas.swift" \
  -o "$BUILD_DIR/verify_local_api_provider_health_quotas"

"$BUILD_DIR/verify_local_api_provider_health_quotas"
