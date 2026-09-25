#!/usr/bin/env bash
# With tab_close_active_only, a close button on an unfocused group must not close
# anything: the click focuses the group instead, so a tab the user was not
# looking at cannot be closed by accident.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"

open_window foot
open_window foot 2
assert_eq "$(group_size foot)" 2 "two windows share the group"
place_frac foot 4 25 40 40

open_window kitty
place_frac kitty 55 55 40 35
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
assert_eq "$(topmost)" kitty "kitty is focused and on top"

read -r cx cy <<<"$(tab_close_point foot 0 2)"
pointer_click "$cx" "$cy"
sleep 0.4

assert_eq "$(group_size foot)" 2 "a close button on an unfocused group closes nothing"
assert_eq "$(active_class)" foot "the click focuses the group instead"
