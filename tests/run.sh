#!/usr/bin/env bash
# x-mode test suite. Static QML lint, the pure-Lua and pure-JS units, then the
# nest scenarios. Prints ok/FAIL per step and exits non-zero on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0

if [ -f "$HERE/lint.sh" ]; then
  echo "== lint"
  bash "$HERE/lint.sh" || fail=1
fi

for d in unit qml nest; do
  [ -f "$HERE/$d/run.sh" ] || continue
  echo "== $d"
  bash "$HERE/$d/run.sh" || fail=1
done

[ "$fail" = 0 ] && echo "== all ok"
exit "$fail"
