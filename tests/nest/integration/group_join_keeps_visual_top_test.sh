#!/usr/bin/env bash
# Regression: adding a window to a group dragged the group up to the top edge.
# The chrome grows by the tabbar when a second window joins, and the clamp then
# resized the group and pinned it against the top instead of leaving it where it
# was with the box moved down by the tabbar.
#
# group_test.sh checks that the tabbar ends up below the bar. This checks the
# other half: the window must not move up while that happens.
. "$(dirname "$0")/../../lib.sh"

open_window foot
read -r _ y1 _ _ _ <<<"$(visible_geom foot)"

open_window foot 2
assert_eq "$(group_size foot)" 2 "the second foot joins the group"

read -r _ y2 _ _ _ <<<"$(visible_geom foot)"

# The tabbar is drawn above the window, so the box has to move down by at least
# its height (24) for the visual top to stay put.
assert_ge "$y2" $((y1 + 24)) "joining a group must push the box down, not pin it to the top"
assert_ge "$y2" 52 "the box sits below the bar plus its own chrome"
assert_ge "$(visual_top foot)" "$(bar_top)" "the tabbar stays below the bar"
