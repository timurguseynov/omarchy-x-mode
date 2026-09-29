#!/usr/bin/env bash
# X Mode switched back on over a tiling desktop. Five foot windows are open and
# tiled when the flag flips, so they are separate windows, not tabs yet. The
# whole switch has to happen behind the fade: every one of the five fades out,
# they gather into one tab group, and they come back together. A fade that only
# reaches the active window leaves the other four on screen through the switch.
#
# Hyprland draws the focused window from "opacity" and every other one from
# "opacity_inactive" (Window.cpp: alpha() vs alphaInactive()), so both are
# sampled: setting only the first is exactly the bug where one window is seen to
# fade.
. "$(dirname "$0")/../../lib.sh"

# Start with X Mode off, so the windows below open tiled.
printf 'off\n' > "$NEST_STATE/state/enabled"
nest_ctl reload >/dev/null
sleep 0.8

open_window foot
open_command foot foot
open_command foot foot
open_command foot foot
open_command foot foot
settle

addrs="$(nest_ctl clients -j | python3 -c 'import json,sys
print(" ".join(c["address"] for c in json.load(sys.stdin) if c["class"] == "foot"))')"
assert_eq "$(wc -w <<<"$addrs")" 5 "five foot windows are open"

tiled="$(nest_ctl clients -j | python3 -c 'import json,sys
print(sum(1 for c in json.load(sys.stdin) if c["class"] == "foot" and not c["floating"]))')"
assert_eq "$tiled" 5 "they start tiled, not grouped"

# Switch X Mode on and sample every window's active and inactive opacity across
# the fade.
samples="$NEST_STATE/op_samples"
: > "$samples"
printf 'on\n' > "$NEST_STATE/state/enabled"
nest_ctl reload >/dev/null
for _ in $(seq 1 40); do
  for a in $addrs; do
    for prop in opacity opacity_inactive; do
      v="$(nest_ctl getprop "address:$a" "$prop" 2>/dev/null || true)"
      [ -n "$v" ] && printf '%s %s %s\n' "$a" "$prop" "$v" >> "$samples"
    done
  done
  sleep 0.03
done

if ! out="$(python3 - "$samples" $addrs 2>&1 <<'PY'
import sys
path, addrs = sys.argv[1], sys.argv[2:]
vals = {}
for line in open(path):
    a, prop, v = line.split()
    try:
        vals.setdefault((a, prop), []).append(float(v))
    except ValueError:
        pass
bad = []
for a in addrs:
    for prop in ("opacity", "opacity_inactive"):
        v = vals.get((a, prop), [])
        if not v:
            bad.append(f"{a[-4:]}: no {prop} samples")
        elif min(v) >= 0.99:
            bad.append(f"{a[-4:]}: {prop} never faded (min {min(v)})")
        elif v[-1] != 1.0:
            bad.append(f"{a[-4:]}: {prop} not revealed (last {v[-1]})")
if bad:
    raise SystemExit("; ".join(bad))
print("all five faded and revealed (active and inactive)")
PY
)"; then
  fail "$out"
fi
printf '%s\n' "$out"

settle
assert_eq "$(group_size foot)" 5 "the five windows end up as tabs of one group"

# Leave the flag where the next scenario expects it.
rm -f "$NEST_STATE/state/enabled"
nest_ctl reload >/dev/null
