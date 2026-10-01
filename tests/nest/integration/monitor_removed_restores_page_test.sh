#!/usr/bin/env bash
# Unplugging a monitor leaves floating windows whole screens away from the one
# that remains: Hyprland translates by the monitor origin, and a later move of
# the survivor can apply that delta again. A left half and a right half shifted
# by the same number of screen widths have to come back to those halves. Pinning
# every off-screen box to the left edge stacks them. A window that only hangs
# off the right of this screen is not on another page, and stays against that
# edge.
. "$(dirname "$0")/../../lib.sh"

open_window foot
settle

nest_ctl dispatch "hl.dsp.window.resize({ x = 100, y = 80, relative = false, window = 'class:foot' })" >/dev/null
settle

read -r px py pw ph <<<"$(nest_ctl monitors -j | python3 -c '
import json, sys
m = next(x for x in json.load(sys.stdin) if x.get("focused"))
s = m["scale"] or 1
print(m["x"], m["y"], m["width"] // s, m["height"] // s)
')"

read -r ww wh <<<"$(nest_ctl clients -j | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c["class"] == "foot":
        print(c["size"][0], c["size"][1]); break
')"

left=$((px + 80))
right=$((px + pw - ww - 80))
[ "$right" -gt $((left + 40)) ] || fail "monitor ${pw}px is too narrow for a ${ww}px window to have two distinct slots"

foot_at() {
  nest_ctl clients -j | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c["class"] == "foot":
        print(c["at"][0], c["at"][1], c["size"][0], c["size"][1]); break
'
}

# Create and destroy an empty output so monitor.removed runs the fit. The
# window under test stays on the original output.
fire_removed() {
  local i
  nest_ctl output create headless HEADLESS-1 >/dev/null 2>&1
  for i in $(seq 1 40); do
    nest_ctl monitors -j | grep -q '"name": "HEADLESS-1"' && break
    sleep 0.1
  done
  settle
  nest_ctl output destroy HEADLESS-1 >/dev/null 2>&1
  for i in $(seq 1 40); do
    nest_ctl monitors -j | grep -q '"name": "HEADLESS-1"' || break
    sleep 0.1
  done
  settle
  sleep 0.3
}

# Place the window at X and unplug. It must come back to EXPECT, the same
# offset on this screen, not to the left edge.
expect_page() {
  local x="$1" expect="$2" label="$3"
  local y=$((py + 80)) ax ay aw ah
  nest_ctl dispatch "hl.dsp.window.move({ x = $x, y = $y, relative = false, window = 'class:foot' })" >/dev/null
  wait_still foot
  read -r ax ay aw ah <<<"$(foot_at)"
  echo "$label placed at $ax,$ay size ${aw}x${ah} (asked $x,$y)"
  assert_between "$ax" $((x - 1)) $((x + 1)) "$label: the off-screen place did not stick"
  fire_removed
  read -r ax ay aw ah <<<"$(foot_at)"
  echo "$label after removal: at $ax,$ay (want $expect)"
  assert_between "$ax" $((expect - 1)) $((expect + 1)) "$label must come back to its own slot, not the left edge"
  assert_eq "$aw" "$ww" "$label: fit must not resize the window"
}

expect_page $((left - pw)) "$left" "left half, one screen left"
expect_page $((right - pw)) "$right" "right half, one screen left"
expect_page $((left - 2 * pw)) "$left" "left half, two screens left"
expect_page $((right - 4 * pw)) "$right" "right half, four screens left"

# Already on this screen: the fit leaves it where it is.
expect_page "$left" "$left" "already inside"

# Hanging off the right, still overlapping this screen. That is the wider
# monitor's right side, not another page, so it stays on the right.
over=$((px + pw - ww / 2))
nest_ctl dispatch "hl.dsp.window.move({ x = $over, y = $((py + 80)), relative = false, window = 'class:foot' })" >/dev/null
wait_still foot
fire_removed
read -r ax ay aw ah <<<"$(foot_at)"
echo "right overhang after removal: at $ax,$ay"
assert_ge "$ax" $((px + pw / 2)) "a window hanging off the right must stay on the right"
assert_between "$ax" "$px" $((px + pw - 1)) "a window hanging off the right must still land on this screen"
