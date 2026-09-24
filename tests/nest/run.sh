#!/usr/bin/env bash
# Start one nested Hyprland and run every nest/*_test.sh against it.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib.sh"

nest_start
trap nest_stop EXIT

fail=0
for t in "$HERE"/*_test.sh; do
  [ -e "$t" ] || continue
  name="$(basename "$t" .sh)"
  nest_clean
  if out="$(bash "$t" 2>&1)"; then
    echo "  ${GREEN}ok${RESET}   $name"
  else
    echo "  ${RED}FAIL${RESET} $name"
    printf '%s\n' "$out" | sed 's/^/       /'
    fail=1
  fi
done
exit "$fail"
