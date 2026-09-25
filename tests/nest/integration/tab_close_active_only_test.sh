#!/usr/bin/env bash
# tab_close_active_only: the close button acts only on the current tab of a
# focused group. Clicking where a background tab's close button is must not close
# it, while the current tab's own close button does.
#
# The index is re-read before the second click: a click on a background tab
# focuses it, so the current tab is not the one it was a moment ago.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
assert_eq "$(group_size foot)" 2 "two windows share the group"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3

cur="$(active_tab_index foot)"
other=0
[ "$cur" = 0 ] && other=1

read -r cx cy <<<"$(tab_close_point foot "$other" 2)"
pointer_click "$cx" "$cy"
sleep 0.4
assert_eq "$(group_size foot)" 2 "a background tab's close button must not close it"

cur="$(active_tab_index foot)"
read -r cx cy <<<"$(tab_close_point foot "$cur" 2)"
pointer_click "$cx" "$cy"
sleep 0.5
assert_eq "$(group_size foot)" 1 "the current tab's close button closes it"
