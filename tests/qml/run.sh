#!/usr/bin/env bash
# QML unit tests: the pure JS the shell plugin shares (quickshell/x-mode/
# logic.js), run with qmltestrunner offscreen. No Quickshell runtime and no
# compositor: importing Quickshell outside the Quickshell binary does not work,
# so components themselves are exercised in the nest instead (tests/nest).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RUNNER="${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"
GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'

if [ ! -x "$RUNNER" ]; then
  echo "  ${RED}FAIL${RESET} qmltestrunner not found at $RUNNER"
  exit 1
fi

out="$(QT_QPA_PLATFORM=offscreen "$RUNNER" -input "$HERE" 2>&1)"
if printf '%s\n' "$out" | grep -q "^FAIL"; then
  printf '%s\n' "$out" | grep -E "^(FAIL|Totals)" | sed 's/^/  /'
  exit 1
fi
printf '%s\n' "$out" | grep -E "^Totals" | sed "s/^/  ${GREEN}ok${RESET}   /"
