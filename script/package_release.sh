#!/bin/bash
set -euo pipefail

APP_NAME="TokenBar"
SCHEME="TokenBar"
PROJECT="TokenBar.xcodeproj"
CONFIGURATION="Release"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_ROOT="${TOKENBAR_RELEASE_ROOT:-$ROOT_DIR/dist/release}"
ARCHIVE_PATH="${TOKENBAR_ARCHIVE_PATH:-$RELEASE_ROOT/archives/$APP_NAME.xcarchive}"
STAGING_DIR="$RELEASE_ROOT/staging"
OUTPUT_DIR="$RELEASE_ROOT/output"
DMG_VOLUME_NAME="${TOKENBAR_DMG_VOLUME_NAME:-TokenBar}"
DMG_FORMAT="${TOKENBAR_DMG_FORMAT:-ULMO}"
SIGNING_MODE="${TOKENBAR_SIGNING:-ad-hoc}"
NOTARIZE="0"

if [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

usage() {
  cat <<'USAGE'
usage: script/package_release.sh [--notarize] [--skip-notarize]

Archives TokenBar, stages a drag-to-Applications DMG, and reports signing and
notarization status without treating missing Apple credentials as complete.

Environment:
  TOKENBAR_SIGNING=ad-hoc|developer-id|automatic
      ad-hoc      Build a local test package without Apple credentials. Default.
      developer-id Require TOKENBAR_DEVELOPMENT_TEAM and a Developer ID identity.
      automatic   Use the signing settings already stored in the Xcode project.

  TOKENBAR_DEVELOPMENT_TEAM=TEAMID
      Apple Developer Team ID for developer-id signing.

  TOKENBAR_CODE_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
      Developer ID app signing identity. Defaults to "Developer ID Application"
      in developer-id mode.

  TOKENBAR_DMG_CODE_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
      Optional identity for signing the DMG container.

  TOKENBAR_DMG_FORMAT=ULMO|UDZO|ULFO|UDRO|...
      Disk image format passed to diskutil/hdiutil. Default: ULMO.

  TOKENBAR_NOTARY_KEYCHAIN_PROFILE=profile-name
      Preferred notarization credential, created with:
      xcrun notarytool store-credentials profile-name --apple-id ... --team-id ...

  TOKENBAR_NOTARY_APPLE_ID=apple@example.com
  TOKENBAR_NOTARY_PASSWORD=app-specific-password
  TOKENBAR_NOTARY_TEAM_ID=TEAMID
      Alternative notarization credentials when no keychain profile is used.

Outputs:
  dist/release/archives/TokenBar.xcarchive
  dist/release/output/TokenBar-<version>-<build>.dmg
USAGE
}

log() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notarize)
      NOTARIZE="1"
      shift
      ;;
    --skip-notarize)
      NOTARIZE="0"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
done

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

require_tool xcodebuild
require_tool codesign
require_tool plutil

notary_args=()
if [[ -n "${TOKENBAR_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  notary_args=(--keychain-profile "$TOKENBAR_NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${TOKENBAR_NOTARY_APPLE_ID:-}" || -n "${TOKENBAR_NOTARY_PASSWORD:-}" || -n "${TOKENBAR_NOTARY_TEAM_ID:-}" ]]; then
  : "${TOKENBAR_NOTARY_APPLE_ID:?TOKENBAR_NOTARY_APPLE_ID is required when using Apple ID notarization}"
  : "${TOKENBAR_NOTARY_PASSWORD:?TOKENBAR_NOTARY_PASSWORD is required when using Apple ID notarization}"
  : "${TOKENBAR_NOTARY_TEAM_ID:?TOKENBAR_NOTARY_TEAM_ID is required when using Apple ID notarization}"
  notary_args=(
    --apple-id "$TOKENBAR_NOTARY_APPLE_ID"
    --password "$TOKENBAR_NOTARY_PASSWORD"
    --team-id "$TOKENBAR_NOTARY_TEAM_ID"
  )
fi

if [[ "$NOTARIZE" == "1" ]]; then
  [[ "$SIGNING_MODE" == "developer-id" ]] || fail "--notarize requires TOKENBAR_SIGNING=developer-id"
  [[ "${#notary_args[@]}" -gt 0 ]] || fail "--notarize requires TOKENBAR_NOTARY_KEYCHAIN_PROFILE or Apple ID notarization env vars"
  require_tool xcrun
fi

cd "$ROOT_DIR"
rm -rf "$ARCHIVE_PATH" "$STAGING_DIR"
mkdir -p "$(dirname "$ARCHIVE_PATH")" "$STAGING_DIR" "$OUTPUT_DIR"

archive_args=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=macOS"
  -archivePath "$ARCHIVE_PATH"
  archive
)

case "$SIGNING_MODE" in
  ad-hoc)
    archive_args+=(
      CODE_SIGN_STYLE=Manual
      CODE_SIGN_IDENTITY=-
      DEVELOPMENT_TEAM=
    )
    ;;
  developer-id)
    : "${TOKENBAR_DEVELOPMENT_TEAM:?TOKENBAR_DEVELOPMENT_TEAM is required for developer-id signing}"
    archive_args+=(
      CODE_SIGN_STYLE=Manual
      CODE_SIGN_IDENTITY="${TOKENBAR_CODE_SIGN_IDENTITY:-Developer ID Application}"
      DEVELOPMENT_TEAM="$TOKENBAR_DEVELOPMENT_TEAM"
    )
    ;;
  automatic)
    ;;
  *)
    fail "TOKENBAR_SIGNING must be ad-hoc, developer-id, or automatic"
    ;;
esac

log "Archiving $APP_NAME ($CONFIGURATION, signing=$SIGNING_MODE)"
xcodebuild "${archive_args[@]}"

APP_BUNDLE="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
[[ -d "$APP_BUNDLE" ]] || fail "archive did not contain $APP_BUNDLE"

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST" 2>/dev/null || printf '0')"
BUILD="$(plutil -extract CFBundleVersion raw "$INFO_PLIST" 2>/dev/null || printf '0')"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION-$BUILD.dmg"

log "Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if ! spctl --assess --type execute --verbose=4 "$APP_BUNDLE"; then
  warn "Gatekeeper assessment did not pass. This is expected for ad-hoc or unnotarized builds."
fi

log "Staging DMG contents"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

log "Creating DMG at $DMG_PATH"
rm -f "$DMG_PATH"
if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from \
    --volumeName "$DMG_VOLUME_NAME" \
    --format "$DMG_FORMAT" \
    "$STAGING_DIR" \
    "$DMG_PATH"
else
  require_tool hdiutil
  hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format "$DMG_FORMAT" \
    "$DMG_PATH"
fi

if [[ -n "${TOKENBAR_DMG_CODE_SIGN_IDENTITY:-}" ]]; then
  log "Signing DMG container"
  codesign --force --timestamp --sign "$TOKENBAR_DMG_CODE_SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
else
  warn "DMG container is unsigned. Set TOKENBAR_DMG_CODE_SIGN_IDENTITY to sign it."
fi

if [[ "$NOTARIZE" == "1" ]]; then
  log "Submitting DMG for notarization"
  xcrun notarytool submit "$DMG_PATH" "${notary_args[@]}" --wait

  log "Stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  warn "Not notarized. Re-run with --notarize after Developer ID signing and notary credentials are configured."
fi

log "Release package complete"
printf 'Archive: %s\n' "$ARCHIVE_PATH"
printf 'DMG:     %s\n' "$DMG_PATH"
printf 'Signing: %s\n' "$SIGNING_MODE"
if [[ "$NOTARIZE" == "1" ]]; then
  printf 'Notary:  submitted and stapled\n'
else
  printf 'Notary:  skipped\n'
fi
