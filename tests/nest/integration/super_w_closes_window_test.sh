#!/usr/bin/env bash
# Super+W closes the window, and with a group the pack hands the focus to the
# next tab of the same group instead of dropping it somewhere else. The binding
# is the pack's own, so this covers the key, the close path and the focus handoff
# together.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
assert_eq "$(group_size foot)" 2 "two windows share the group"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3

key super+w
sleep 0.6

assert_eq "$(count_class foot)" 1 "Super+W closes the focused window"
assert_eq "$(active_class)" foot "the focus stays in the group"
