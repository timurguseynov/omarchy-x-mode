#!/usr/bin/env bash
# Regression: clicking the titlebar of a window in the background focused it but
# left it behind. The raise was deferred by a millisecond and re-read the live
# active window, so it could raise a different one; a raise_pending that never
# cleared swallowed every later raise.
#
# The windows are parked apart so the click has exactly one answer.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window kitty
place_frac foot 4 30 35 35
place_frac kitty 58 30 35 35

nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
assert_eq "$(topmost)" kitty "kitty is on top to begin with"

read -r tx ty <<<"$(titlebar_point foot)"
pointer_click "$tx" "$ty"
sleep 0.3

assert_eq "$(active_class)" foot "clicking a titlebar focuses that window"
assert_eq "$(topmost)" foot "clicking a titlebar raises that window"
