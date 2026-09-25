#!/usr/bin/env bash
# Closing the current tab with the tabbar's close button keeps the focus in the
# group and leaves the group on top of another app. The pack turns on
# tab_close_active_only, so only the current tab's close button acts.
#
# Two tabs: the tabbar splits its width after the 34px + button, and the close
# button is the last 24px of a tab, so the geometry is only simple to hit while
# the split is wide.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
assert_eq "$(group_size foot)" 2 "two windows share the group"

open_window kitty
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
assert_eq "$(topmost)" foot "the group is on top before closing"

idx="$(active_tab_index foot)"
read -r cx cy <<<"$(tab_close_point foot "$idx" 2)"
pointer_click "$cx" "$cy"
sleep 0.5

assert_eq "$(group_size foot)" 1 "the current tab closes"
assert_eq "$(active_class)" foot "the focus stays in the group"
assert_eq "$(topmost)" foot "the group is still raised"
