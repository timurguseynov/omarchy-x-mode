#!/usr/bin/env bash
# Super+W on a window that is not in a group closes it and leaves the other app
# alone. The group path is covered elsewhere; this is the other branch.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window kitty

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3

key super+w
sleep 0.6

assert_eq "$(count_class foot)" 0 "Super+W closes the focused window"
assert_eq "$(count_class kitty)" 1 "the other app keeps running"
