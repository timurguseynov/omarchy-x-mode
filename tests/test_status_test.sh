#!/usr/bin/env bash
# Node's reporter is not a nest verdict. Keep its diagnostics, then emit one
# suite-format result so async.sh never mistakes a Node failure for FAIL: 0.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if node --test "$@" "$HERE/test_status_test.mjs"; then
  echo "  ok   test_status_test"
else
  echo "  FAIL test_status_test"
  exit 1
fi
