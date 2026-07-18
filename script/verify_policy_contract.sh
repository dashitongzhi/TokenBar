#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/policy-contract"

if [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

mkdir -p "$BUILD_DIR"
xcrun --sdk macosx swiftc \
  "$ROOT_DIR/TokenBar/Core/AppPresentationModels.swift" \
  "$ROOT_DIR/TokenBar/Core/ProviderUsageModels.swift" \
  "$ROOT_DIR/TokenBar/Core/SmartRoutingModels.swift" \
  "$ROOT_DIR/TokenBar/Core/WorkspacePolicyModels.swift" \
  "$ROOT_DIR/TokenBar/App/PolicyEngine.swift" \
  "$ROOT_DIR/TokenBarTests/PolicyContractFixtureVerifier.swift" \
  "$ROOT_DIR/script/verify_policy_contract.swift" \
  -o "$BUILD_DIR/verify_policy_contract"

"$BUILD_DIR/verify_policy_contract" "$ROOT_DIR/script/fixtures/policy_contract.json"
