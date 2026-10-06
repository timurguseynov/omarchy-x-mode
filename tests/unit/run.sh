#!/usr/bin/env bash
# Unit tests: pure Lua, no compositor. Each *_test.lua runs with plain lua and
# exits non-zero on failure.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
RED=$'\033[31m'; GREEN=$'\033[32m'; RESET=$'\033[0m'

fail=0
# Every test runs against a throwaway HOME and state dir. Nothing in the unit
# layer needs the real ones, and a test that loads the config can neither read
# nor write the session's files through them.
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/home" "$SANDBOX/state"
for t in "$HERE"/*_test.lua; do
  [ -e "$t" ] || continue
  name="$(basename "$t" .lua)"
  if out="$(HOME="$SANDBOX/home" X_MODE_STATE="$SANDBOX/state" X_MODE_REPO="$REPO" lua "$t" 2>&1)"; then
    echo "  ${GREEN}ok${RESET}   $name"
  else
    echo "  ${RED}FAIL${RESET} $name"
    printf '%s\n' "$out" | sed 's/^/       /'
    fail=1
  fi
done
exit "$fail"
