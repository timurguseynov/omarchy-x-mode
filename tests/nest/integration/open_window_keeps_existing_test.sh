#!/usr/bin/env bash
# Regression: on window.open, keep_below_topbar ran over every window. Hyprland
# re-centres on resize, so a window that already sat below the bar jumped up to
# the minimum top when an unrelated window opened. Only the window that just
# opened may be clamped.
#
# A second app, not a second foot: a same-app window joins the group on purpose
# and moves the first one down by the tabbar height. That is group_test.sh's job.
. "$(dirname "$0")/../../lib.sh"

open_window foot
read -r fx fy _ _ _ <<<"$(win_geom foot)"
assert_ge "$fy" 36 "the window starts below the bar"

open_window kitty

read -r fx2 fy2 _ _ _ <<<"$(win_geom foot)"
assert_eq "$fx2" "$fx" "opening another app must not move the existing window"
assert_eq "$fy2" "$fy" "opening another app must not move the existing window"
assert_ge "$(visual_top foot)" 36 "the existing window still clears the bar"
assert_ge "$(visual_top kitty)" 36 "the new window clears the bar"

# A third window, same app as the second: it joins kitty's group, so foot must
# still not move.
read -r kx ky _ _ _ <<<"$(win_geom kitty)"
open_window kitty 2

read -r fx3 fy3 _ _ _ <<<"$(win_geom foot)"
assert_eq "$fx3" "$fx" "a joining window must not move an unrelated app"
assert_eq "$fy3" "$fy" "a joining window must not move an unrelated app"
assert_ge "$(visual_top foot)" 36 "foot still clears the bar"
