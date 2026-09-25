#!/usr/bin/env bash
# Super+Q on a window that is not in a group closes just that window: the group
# branch of the handler has nothing to walk.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window kitty
assert_eq "$(count_class foot)" 1 "one window to close"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3

key super+q
sleep 0.6

assert_eq "$(count_class foot)" 0 "Super+Q closes the ungrouped window"
assert_eq "$(count_class kitty)" 1 "the other app keeps running"
