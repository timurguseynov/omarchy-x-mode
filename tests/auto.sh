#!/usr/bin/env bash
# Run the suite, and when it is red shrink the nest failures without asking
# the model to start each smaller run. The suite's own output is kept beside
# the receipt, so a red line is not rewritten into a pass. The receipt itself
# contains only the final disposition: a name that passes in the smaller run
# is left alone, and a name that fails alone stays red.
#
#   bash tests/async.sh run suite bash tests/auto.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
full="${XMODE_TEST_LOG:-$(mktemp)}"
suite="${AUTO_SUITE:-$HERE/run.sh}"
printf 'suite log: %s.suite\n' "$full"
bash "$suite" >"$full.suite" 2>&1
rc=$?
printf 'suite exit: %s\n' "$rc"
if [ "$rc" -eq 0 ]; then
  echo "  ok   suite"
  echo "== all ok"
  exit 0
fi
exec bash "$HERE/funnel.sh" "$full.suite"
