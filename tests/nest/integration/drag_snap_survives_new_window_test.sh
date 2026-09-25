#!/usr/bin/env bash
# Regression: while one window was being dragged, a new window opening stole the
# focus, and the drag preview and the snap were bound to the focused window. So
# the preview died, or the pending snap landed on the window that had just
# opened instead. The gesture has to stay bound to the window being dragged.
#
# Driven through one pointer session so a window can be opened mid-drag.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"
mh="${extent#*x}"

open_window foot
read -r tx ty <<<"$(titlebar_point foot)"

pointer_begin
pointer_do "move $tx $ty"
pointer_do "press left"
pointer_do "move $((tx - 20)) $((ty + 20))"
pointer_do "move $((tx - 40)) $((ty + 40))"

# A new app appears while the button is still down.
open_window kitty
read -r kx ky kw kh _ <<<"$(win_geom kitty)"

# Drop in the left strip.
pointer_do "move 6 $((mh / 2))"
pointer_do "move 5 $((mh / 2))"
pointer_do "release left"
pointer_end
sleep 0.4

read -r fx _ fw _ _ <<<"$(win_geom foot)"
assert_le "$fx" 20 "the dragged window is the one that snaps"
assert_le "$fw" $((mw * 6 / 10)) "the dragged window took a half"

read -r kx2 ky2 kw2 kh2 _ <<<"$(win_geom kitty)"
assert_eq "$kx2" "$kx" "the window opened mid-drag must not be moved"
assert_eq "$ky2" "$ky" "the window opened mid-drag must not be moved"
assert_eq "$kw2" "$kw" "the window opened mid-drag must not be resized"
assert_eq "$kh2" "$kh" "the window opened mid-drag must not be resized"
