#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/TokenBar/App/SmartRoutingCostMetrics.swift" \
  "$ROOT_DIR/script/verify_smart_routing_cost_metrics.swift" \
  -o "$BUILD_DIR/verify_smart_routing_cost_metrics"

"$BUILD_DIR/verify_smart_routing_cost_metrics"
