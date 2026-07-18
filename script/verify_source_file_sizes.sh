#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAX_LINES="${TOKENBAR_MAX_SOURCE_LINES:-400}"

if [[ ! "$MAX_LINES" =~ ^[0-9]+$ ]] || [[ "$MAX_LINES" -lt 1 ]]; then
  printf 'TOKENBAR_MAX_SOURCE_LINES must be a positive integer\n' >&2
  exit 2
fi

failed=0
while IFS= read -r -d '' file; do
  lines="$(wc -l < "$file" | tr -d '[:space:]')"
  if (( lines > MAX_LINES )); then
    printf 'Source file exceeds %s lines: %s (%s)\n' "$MAX_LINES" "${file#"$ROOT_DIR/"}" "$lines" >&2
    failed=1
  fi
done < <(find "$ROOT_DIR/TokenBar" "$ROOT_DIR/lib" -type f \( -name '*.swift' -o -name '*.rb' \) -print0)

if (( failed != 0 )); then
  exit 1
fi

printf 'Verified Swift and Ruby source files stay at or below %s lines.\n' "$MAX_LINES"
