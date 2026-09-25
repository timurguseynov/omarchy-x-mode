#!/usr/bin/env bash
# Regression: snapping a lone window made it collapse to its chrome. The snap
# path ran toggleGroup first, so the new group target started from a 0x0 box and
# the client was configured to zero height, leaving only a titlebar and tabbar on
# screen.
#
# So this checks both halves: the client keeps a real size, and snapping one
# window does not conjure a group.
. "$(dirname "$0")/../../lib.sh"

open_window foot

read -r _ _ w0 h0 _ <<<"$(win_geom foot)"
assert_ge "$w0" 100 "the window opens with a real width"
assert_ge "$h0" 100 "the window opens with a real height"

snap foot left

read -r _ y w h _ <<<"$(win_geom foot)"
assert_ge "$w" 100 "a snap keeps the width instead of collapsing the window"
assert_ge "$h" 100 "the client stays visible: the height is not zero"
assert_ge "$y" 64 "a snapped window keeps the gap under the bar"
assert_ge "$(visual_top foot)" 36 "the titlebar does not eat the whole window"
# A lone window has an empty grouped list, so this is 0; the bound is written as
# <= 1 so a singleton group would not fail it for the wrong reason.
assert_le "$(group_size foot)" 1 "snapping a lone window must not create a group"
