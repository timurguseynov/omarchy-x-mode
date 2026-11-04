#!/usr/bin/env bash
# Run the suite, and when it is red shrink the nest failures without asking
# the model to start each smaller run. The suite's own output is kept beside
# the receipt, so a red line is not rewritten into a pass. The receipt names
# the original counts on one == suite line, which is not a scenario result, and
# then only the final disposition: a name that passes in the smaller run is
# left alone, and a name that fails alone stays red.
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
# Counted the same way the status file counts a receipt, but from the suite log.
# Printed as a summary, not as `  ok` / `  FAIL`, so a failure that the shrink
# later clears is visible here and is not counted red again.
python3 - "$full.suite" "$rc" <<'PY'
import re, sys
strip = re.compile(r'\x1b\[[0-9;]*m')
ok = fail = warn = notrun = 0
for raw in open(sys.argv[1], errors='replace'):
    line = strip.sub('', raw).rstrip('\n')
    m = re.match(r'^  (ok|FAIL|NOT RUN) +(\S+)', line)
    if m:
        kind = m.group(1)
        if kind == 'ok':
            ok += 1
        elif kind == 'FAIL':
            fail += 1
        else:
            notrun += 1
    elif 'hyprland reported an error' in line:
        warn += 1
print('== suite: ok %d  FAIL %d  WARN %d  NOT RUN %d  exit %s' % (ok, fail, warn, notrun, sys.argv[2]))
PY
if [ "$rc" -eq 0 ]; then
  echo "  ok   suite"
  echo "== all ok"
  exit 0
fi
exec bash "$HERE/funnel.sh" "$full.suite"
