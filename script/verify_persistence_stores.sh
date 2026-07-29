#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/TokenBar/Core/AppPresentationModels.swift" \
  "$ROOT_DIR/TokenBar/Core/ProviderUsageModels.swift" \
  "$ROOT_DIR/TokenBar/Core/WorkspacePolicyModels.swift" \
  "$ROOT_DIR/TokenBar/Core/LocalUsageModels.swift" \
  "$ROOT_DIR/TokenBar/Core/SmartRoutingModels.swift" \
  "$ROOT_DIR/TokenBar/Core/SmartRoutingCostMetrics.swift" \
  "$ROOT_DIR/TokenBar/Core/SmartRoutingRecommendationEligibility.swift" \
  "$ROOT_DIR/TokenBar/App/JSONDocumentStore.swift" \
  "$ROOT_DIR/TokenBar/App/WorkspacePolicyStore.swift" \
  "$ROOT_DIR/TokenBar/App/LocalAgentUsageLedgerStore.swift" \
  "$ROOT_DIR/TokenBar/App/LocalModelUsageStore.swift" \
  "$ROOT_DIR/TokenBar/App/SmartRoutingLedgerStore.swift" \
  "$ROOT_DIR/script/verify_persistence_stores.swift" \
  -o "$BUILD_DIR/verify_persistence_stores"

TZ=UTC "$BUILD_DIR/verify_persistence_stores"
