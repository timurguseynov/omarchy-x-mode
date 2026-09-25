#!/usr/bin/env bash
# Regression: clicking the right window's titlebar raised the left one. The raise
# ran a millisecond later and re-read the live active window, and with two
# windows the focus had not settled, so the wrong window came to the front.
#
# So this checks both directions: the clicked window is on top, and the other one
# did not move at all.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window kitty
place_frac foot 4 30 35 35
place_frac kitty 58 30 35 35

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
assert_eq "$(topmost)" foot "foot is on top to begin with"

read -r fx fy _ _ _ <<<"$(win_geom kitty)"

read -r tx ty <<<"$(titlebar_point kitty)"
pointer_click "$tx" "$ty"
sleep 0.3

assert_eq "$(topmost)" kitty "clicking the right window raises the right window"
assert_eq "$(active_class)" kitty "the click focuses the clicked window"
read -r fx2 fy2 _ _ _ <<<"$(win_geom kitty)"
assert_eq "$fx2" "$fx" "the click must not move the clicked window"
assert_eq "$fy2" "$fy" "the click must not move the clicked window"
