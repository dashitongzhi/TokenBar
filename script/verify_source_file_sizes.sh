#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOFT_LINES="${TOKENBAR_SOFT_SOURCE_LINES:-400}"
HARD_LINES="${TOKENBAR_HARD_SOURCE_LINES:-700}"
GROWTH_LINES="${TOKENBAR_SOURCE_GROWTH_LINES:-80}"
EXEMPTIONS_FILE="$ROOT_DIR/script/source_size_exemptions.txt"

for setting in SOFT_LINES HARD_LINES GROWTH_LINES; do
  value="${!setting}"
  if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 1 ]]; then
    printf '%s must be a positive integer\n' "$setting" >&2
    exit 2
  fi
done
if (( SOFT_LINES >= HARD_LINES )); then
  printf 'TOKENBAR_SOFT_SOURCE_LINES must be lower than TOKENBAR_HARD_SOURCE_LINES\n' >&2
  exit 2
fi

is_exempt() {
  local relative_path="$1"
  [[ -f "$EXEMPTIONS_FILE" ]] || return 1
  awk -F '|' -v path="$relative_path" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $1 == path && length($2) >= 12 { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$EXEMPTIONS_FILE"
}

baseline_lines() {
  local relative_path="$1"
  if git -C "$ROOT_DIR" cat-file -e "HEAD:$relative_path" 2>/dev/null; then
    git -C "$ROOT_DIR" show "HEAD:$relative_path" | wc -l | tr -d '[:space:]'
  else
    printf '0\n'
  fi
}

failed=0
warned=0
while IFS= read -r -d '' file; do
  lines="$(wc -l < "$file" | tr -d '[:space:]')"
  relative_path="${file#"$ROOT_DIR/"}"
  if (( lines > HARD_LINES )); then
    printf 'Source file exceeds hard limit %s: %s (%s)\n' "$HARD_LINES" "$relative_path" "$lines" >&2
    failed=1
    continue
  fi
  if (( lines <= SOFT_LINES )) || is_exempt "$relative_path"; then
    continue
  fi

  previous_lines="$(baseline_lines "$relative_path")"
  if [[ "$previous_lines" =~ ^[0-9]+$ ]] &&
     (( previous_lines > 0 )) &&
     (( lines > previous_lines + GROWTH_LINES )); then
    printf 'Source file grew by more than %s lines above the soft threshold: %s (%s -> %s)\n' \
      "$GROWTH_LINES" "$relative_path" "$previous_lines" "$lines" >&2
    failed=1
  else
    printf 'Source-size advisory: review %s (%s lines) for a single coherent responsibility; split only at a real boundary or document an exemption.\n' \
      "$relative_path" "$lines" >&2
    warned=1
  fi
done < <(find "$ROOT_DIR/TokenBar" "$ROOT_DIR/lib" -type f \( -name '*.swift' -o -name '*.rb' \) -print0)

if (( failed != 0 )); then
  exit 1
fi

if (( warned != 0 )); then
  printf 'Verified source files stay below the hard limit; soft-limit files require responsibility review.\n'
else
  printf 'Verified source files stay below the %s-line soft responsibility threshold and %s-line hard limit.\n' \
    "$SOFT_LINES" "$HARD_LINES"
fi
