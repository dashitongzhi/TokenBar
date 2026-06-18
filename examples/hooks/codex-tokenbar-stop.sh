#!/usr/bin/env bash
set -u

TOKENBAR_BIN="${TOKENBAR_BIN:-tokenbar}"

"$TOKENBAR_BIN" usage codex-session >/dev/null 2>&1 || true
