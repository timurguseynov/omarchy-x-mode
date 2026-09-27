#!/usr/bin/env bash
# The arrange that runs on a fresh install and again when X Mode is switched
# back on fades the open windows out first, deals them into halves while they
# are invisible, then brings them back at full opacity in one step. Otherwise
# the windows are seen jumping from wherever they were into a half. This pins
# the fade (opacity drops below 1) and the reveal (it ends back at 1), not the
# exact curve mid-way.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window kitty

touch "$NEST_STATE/state/arrange"
nest_ctl reload >/dev/null

# The fade runs on the 600ms arrange timer, the reveal follows it a moment
# later, so sample across the whole window rather than at one fixed moment (a
# late timer would make a single sample flaky).
vals=""
for _ in $(seq 1 40); do
  v="$(nest_ctl getprop class:foot opacity 2>/dev/null || true)"
  [ -n "$v" ] && vals="$vals $v"
  sleep 0.03
done

read -r fx _ <<<"$(win_geom foot)"
read -r kx _ <<<"$(win_geom kitty)"
assert_ne "$fx" "$kx" "the arrange still lands the windows on different sides"

if ! out="$(python3 - "$vals" <<'PY' 2>&1
import sys
vals = [float(x) for x in sys.argv[1].split()]
if not vals:
    raise SystemExit("no opacity samples")
if min(vals) >= 0.99:
    raise SystemExit(f"no fade seen: min opacity {min(vals)}")
if vals[-1] != 1.0:
    raise SystemExit(f"not revealed: last opacity {vals[-1]}")
print(f"faded to {min(vals)}, ended at {vals[-1]}")
PY
)"; then
  fail "$out"
fi
printf '%s\n' "$out"
