#!/usr/bin/env bash
# Regression: switching tabs inside a group changed the window geometry. The
# hidden member reported desiredExtents 0, so the group's shared box was
# recomputed for a frame and the client got a configure with a different height
# (a status bar blink, seen in zed).
#
# visible_geom, not win_geom: the inactive tab stays mapped, and its box is not
# the one on screen.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
assert_eq "$(group_size foot)" 2 "the second foot joins the group"

read -r x1 y1 w1 h1 _ <<<"$(visible_geom foot)"
top1="$(visual_top foot)"

group_tab 1 foot
read -r x2 y2 w2 h2 _ <<<"$(visible_geom foot)"
assert_eq "$x2" "$x1" "x must not change when the tab switches"
assert_eq "$y2" "$y1" "y must not change when the tab switches"
assert_eq "$w2" "$w1" "width must not change when the tab switches"
assert_eq "$h2" "$h1" "height must not change when the tab switches"
assert_eq "$(visual_top foot)" "$top1" "the visual top must not move when the tab switches"

group_tab 2 foot
read -r x3 y3 w3 h3 _ <<<"$(visible_geom foot)"
assert_eq "$x3" "$x1" "x must not change switching back either"
assert_eq "$y3" "$y1" "y must not change switching back either"
assert_eq "$w3" "$w1" "width must not change switching back either"
assert_eq "$h3" "$h1" "height must not change switching back either"
assert_ge "$(visual_top foot)" "$(bar_top)" "the tabbar stays below the bar"
