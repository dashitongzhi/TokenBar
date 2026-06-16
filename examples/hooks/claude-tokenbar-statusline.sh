#!/usr/bin/env bash
set -u

TOKENBAR_BIN="${TOKENBAR_BIN:-tokenbar}"

"$TOKENBAR_BIN" usage claude-statusline 2>/dev/null || printf "TokenBar offline\n"
