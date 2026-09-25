#!/usr/bin/env bash
# Super+Alt+F maximizes to the workarea, and Ctrl+Alt+Down puts back the geometry
# the window had before, so the two keys are a pair rather than a one-way trip.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"

open_window foot
key super+alt+left
sleep 0.4
read -r bx by bw bh _ <<<"$(win_geom foot)"

key super+alt+f
sleep 0.4
read -r _ _ xw _ _ <<<"$(win_geom foot)"
assert_ge "$xw" $((mw * 8 / 10)) "Super+Alt+F fills the workarea"

key ctrl+alt+down
sleep 0.4
read -r rx ry rw rh _ <<<"$(win_geom foot)"
assert_eq "$rx" "$bx" "Ctrl+Alt+Down restores the x the window had"
assert_eq "$ry" "$by" "Ctrl+Alt+Down restores the y the window had"
assert_eq "$rw" "$bw" "Ctrl+Alt+Down restores the width the window had"
assert_eq "$rh" "$bh" "Ctrl+Alt+Down restores the height the window had"
