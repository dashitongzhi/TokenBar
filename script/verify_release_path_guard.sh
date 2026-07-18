#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/package_release.sh"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tokenbar-release-guard.XXXXXX")"
RELEASE_ROOT_INPUT="$TEST_ROOT/release"
ARCHIVE_PATH_INPUT=""
prepare_release_paths

inside_file="$RELEASE_ROOT/removable"
outside_file="$TEST_ROOT/outside"
printf 'inside\n' > "$inside_file"
printf 'outside\n' > "$outside_file"

safe_remove_release_path "$inside_file"
[[ ! -e "$inside_file" ]] || {
  printf 'error: safe release file was not removed\n' >&2
  exit 1
}

if (safe_remove_release_path "$RELEASE_ROOT/../outside") >/dev/null 2>&1; then
  printf 'error: traversal path escaped the release root\n' >&2
  exit 1
fi
[[ -f "$outside_file" ]] || {
  printf 'error: traversal guard failed to preserve outside file\n' >&2
  exit 1
}

if (safe_remove_release_path "$RELEASE_ROOT") >/dev/null 2>&1; then
  printf 'error: release root removal was allowed\n' >&2
  exit 1
fi

RELEASE_ROOT_INPUT="/"
if (prepare_release_paths) >/dev/null 2>&1; then
  printf 'error: filesystem root was accepted as release root\n' >&2
  exit 1
fi

printf 'Verified release cleanup rejects root and traversal paths.\n'
