#!/usr/bin/env bash
# Static QML check: qmllint over the shell plugin. The Quickshell and qs.*
# modules are not on the lint import path, so their "not found" warnings are
# expected; only real errors fail.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
QMLDIR="$HERE/../quickshell/x-mode"
LINT="${QMLLINT:-/usr/lib/qt6/bin/qmllint}"
GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'

if [ ! -x "$LINT" ]; then
  echo "  ${RED}FAIL${RESET} qmllint not found at $LINT"
  exit 1
fi

fail=0
for f in "$QMLDIR"/*.qml; do
  out="$(QT_QPA_PLATFORM=offscreen "$LINT" "$f" 2>&1)"
  errs="$(printf '%s\n' "$out" | grep -E "Error:" || true)"
  if [ -n "$errs" ]; then
    echo "  ${RED}FAIL${RESET} $(basename "$f")"
    printf '%s\n' "$errs" | sed 's/^/       /'
    fail=1
  fi
done

[ "$fail" = 0 ] && echo "  ${GREEN}ok${RESET}   qmllint (missing Quickshell/qs imports warn, they do not fail)"
exit "$fail"
