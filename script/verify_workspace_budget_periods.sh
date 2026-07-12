#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
APP_EXEC="$DERIVED_DATA/Build/Products/Debug/TokenBar.app/Contents/MacOS/TokenBar"

if [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

xcodebuild \
  -project "$ROOT_DIR/TokenBar.xcodeproj" \
  -scheme TokenBar \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  ENABLE_DEBUG_DYLIB=NO \
  CODE_SIGNING_ALLOWED="${TOKENBAR_CODE_SIGNING_ALLOWED:-NO}" \
  build

"$APP_EXEC" --tokenbar-verify-workspace-budget-periods
