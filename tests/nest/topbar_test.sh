#!/usr/bin/env bash
# The bar is a layer surface and is gone for a moment while the shell restarts.
# A snap in that window must still clear where the bar was: the plugin remembers
# the last non-zero top instead of reading the monitor's zero.
. "$(dirname "$0")/../lib.sh"

assert_ge "$(bar_top)" 24 "the nest bar reserves the top"

open_window foot
nest_bar_stop
sleep 0.3
assert_eq "$(bar_top)" 0 "bar gone: the monitor reports no top"

snap foot left
assert_ge "$(win_geom foot | awk '{print $2}')" 25 "the snap still clears the bar"

nest_bar_start
