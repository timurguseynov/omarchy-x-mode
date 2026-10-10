#!/usr/bin/env bash
# compactTabs on one class is a window rule, so only that app gets the one-row
# strip. alwaysTabbar on the same class must not grow a second row either.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"
printf '%s\n' '{"options":{},"apps":{"foot":{"chrome":true,"alwaysTabbar":true,"compactTabs":true}}}' > "$SETTINGS"
refresh_apps

open_window foot
snap foot left

read -r _ y _ _ _ <<<"$(win_geom foot)"
# Two-row always-tabbar is 88 (bar + gaps + titlebar + tabbar). One compact
# row lands around 64; leave slop for the gap/border without allowing a tab row.
assert_ge "$y" 50 "the titlebar still sits below the bar"
assert_le "$y" 80 "alwaysTabbar must not add a second row when compact"

open_window foot 2
assert_eq "$(group_size foot)" 2 "the second foot still groups"

read -r _ y2 _ _ _ <<<"$(win_geom foot)"
assert_eq "$y2" "$y" "a per-app compact group keeps one chrome row"

# Three tabs in a narrow box have to shrink below the 240px cap, and still
# leave the drag handle.
place_frac foot 10 20 28 50
read -r _ _ bw _ _ <<<"$(visible_geom foot)"
open_window foot 3
assert_eq "$(group_size foot)" 3 "three windows share the group"
read -r left tabw plusx plusw bh <<<"$(compact_strip foot 3)"
python3 -c "
tabw, plusx, plusw, bw = float('$tabw'), float('$plusx'), float('$plusw'), float('$bw')
assert tabw < 240, f'narrow tabs must shrink, got {tabw}'
assert plusx + plusw + 40 <= bw + 1, f'shrunken tabs ate the drag handle: plusx={plusx} plusw={plusw} bw={bw}'
"
