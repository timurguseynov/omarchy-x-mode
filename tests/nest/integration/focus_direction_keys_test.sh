#!/usr/bin/env bash
# Super+Left and Super+Right focus the window in that direction. The two windows
# are parked apart so "left" has one answer.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window kitty
place_frac foot 4 30 35 35
place_frac kitty 58 30 35 35

nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
assert_eq "$(active_class)" kitty "kitty is focused to begin with"

key super+left
sleep 0.4
assert_eq "$(active_class)" foot "Super+Left focuses the window on the left"

key super+right
sleep 0.4
assert_eq "$(active_class)" kitty "Super+Right focuses it back"
