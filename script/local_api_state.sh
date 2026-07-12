#!/usr/bin/env bash

tokenbar_container_state_dir() {
  printf '%s\n' "$HOME/Library/Containers/Kral.TokenBar/Data/Library/Application Support/TokenBar"
}

tokenbar_legacy_state_dir() {
  printf '%s\n' "$HOME/Library/Application Support/TokenBar"
}

tokenbar_api_token_path() {
  if [[ -n "${TOKENBAR_API_TOKEN_PATH:-}" ]]; then
    printf '%s\n' "$TOKENBAR_API_TOKEN_PATH"
    return 0
  fi

  local directory candidate
  for directory in "$(tokenbar_container_state_dir)" "$(tokenbar_legacy_state_dir)"; do
    candidate="$directory/local-api-token"
    if [[ -r "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}
