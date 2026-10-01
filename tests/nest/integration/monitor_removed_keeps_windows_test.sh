#!/usr/bin/env bash
# Unplugging a monitor must not lose the windows that were on it. Hyprland
# hands the removed monitor's workspaces to the one that is left, but for a
# floating window it only translates the position by the monitor offset: a
# window on the right of a wide external screen ends up past the right edge of
# a narrower built-in one, on no pixel the user can reach. x-mode has to pull
# it back into the remaining monitor's frame.
. "$(dirname "$0")/../../lib.sh"

open_window foot
settle

nest_ctl output create headless HEADLESS-1 >/dev/null 2>&1
for i in $(seq 1 40); do
  nest_ctl monitors -j | grep -q '"name": "HEADLESS-1"' && break
  sleep 0.1
done
settle

# A window on the second output, on its right side: the same place a window on
# the right of a wider external screen is. Move it to that monitor's active
# workspace, so the workspace is the one the removal has to hand over.
nest_ctl dispatch "hl.dsp.window.move({ monitor = \"HEADLESS-1\", window = 'class:foot' })" >/dev/null
settle

read -r px py pw ph hx hy hw hh <<<"$(nest_ctl monitors -j | python3 -c '
import json, sys
primary = headless = None
for m in json.load(sys.stdin):
    s = m["scale"]
    box = (m["x"], m["y"], m["width"] // s, m["height"] // s)
    if m["name"] == "HEADLESS-1":
        headless = box
    else:
        primary = box
print(*primary, *headless)
')"

read -r ww wh <<<"$(nest_ctl clients -j | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c["class"] == "foot":
        print(c["size"][0], c["size"][1]); break
')"

wx=$((hx + hw - ww - 20))
wy=$((hy + 60))
nest_ctl dispatch "hl.dsp.window.move({ x = $wx, y = $wy, relative = false, window = 'class:foot' })" >/dev/null
settle

# Unplug it.
nest_ctl output destroy HEADLESS-1 >/dev/null 2>&1
settle
sleep 0.4

read -r x y w h mapped <<<"$(nest_ctl clients -j | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c["class"] == "foot":
        print(c["at"][0], c["at"][1], c["size"][0], c["size"][1], 1 if c["mapped"] else 0); break
')"

echo "window after removal: at $x,$y size ${w}x${h} mapped=$mapped"
echo "remaining monitor:    at $px,$py size ${pw}x${ph}"

assert_eq "$mapped" 1 "the window must stay mapped after its monitor is gone"
assert_between "$x" "$px" $((px + pw - 1)) "the window must land inside the remaining monitor, not off its right edge"
assert_between "$y" "$py" $((py + ph - 1)) "the window must land inside the remaining monitor vertically"
