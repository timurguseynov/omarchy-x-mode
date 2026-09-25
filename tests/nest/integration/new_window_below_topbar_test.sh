#!/usr/bin/env bash
# Regression: a newly opened window climbed over the topbar. When the bar was
# briefly gone, usable(mon).top read 0 and there was nothing left to remember
# the bar height by, so the clamp had no floor. Both a lone window and one that
# joins a group have to land below the bar.
#
# The bound is bar_top, not the 36 snap_test.sh uses: 36 is the gaps-on inset,
# and this has to keep holding whatever the gaps are.
. "$(dirname "$0")/../../lib.sh"

bar="$(bar_top)"
assert_ge "$bar" 1 "the bar has to be there, or this test proves nothing"

open_window foot
assert_ge "$(visual_top foot)" "$bar" "a lone new window must not climb over the bar"

open_window foot 2
assert_eq "$(group_size foot)" 2 "the second foot joins the group"
assert_ge "$(visual_top foot)" "$bar" "a window joining a group must not climb over the bar"
