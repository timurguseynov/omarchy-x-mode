#!/usr/bin/env bash
# Super+Q closes the whole app: every tab of the group, not just the focused one.
# Another app is left running so the test can tell "closed the app" from "closed
# everything".
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
open_window foot 3
open_window kitty
assert_eq "$(group_size foot)" 3 "three windows share the group"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3

key super+q
sleep 0.8

assert_eq "$(count_class foot)" 0 "Super+Q closes every tab of the app"
assert_eq "$(count_class kitty)" 1 "the other app keeps running"
