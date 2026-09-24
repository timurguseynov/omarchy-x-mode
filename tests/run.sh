#!/usr/bin/env bash
# x-mode test suite. Unit tests first (no compositor), then the nest scenarios.
# Prints ok/FAIL per file and exits non-zero if anything failed.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0

for d in unit nest; do
  [ -f "$HERE/$d/run.sh" ] || continue
  echo "== $d"
  bash "$HERE/$d/run.sh" || fail=1
done

[ "$fail" = 0 ] && echo "== all ok"
exit "$fail"
