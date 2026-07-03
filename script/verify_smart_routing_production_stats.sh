#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/tokenbar-regression"
mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/TokenBar/App/SmartRoutingRecommendationEligibility.swift" \
  "$ROOT_DIR/script/verify_smart_routing_production_stats.swift" \
  -o "$BUILD_DIR/verify_smart_routing_production_stats"

"$BUILD_DIR/verify_smart_routing_production_stats" "$@"
