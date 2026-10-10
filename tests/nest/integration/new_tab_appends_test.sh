#!/usr/bin/env bash
# A new same-app window is the last tab, not the slot after the current one.
# Hyprland's default is group:insert_after_current; the pack turns that off so
# opening a window while looking at an earlier tab still appends.
. "$(dirname "$0")/../../lib.sh"

open_window foot
a="$(active_address)"
open_window foot 2
b="$(active_address)"
open_window foot 3
c="$(active_address)"
wait_until 3 '[ "$(group_size foot)" = 3 ]' || fail "three windows did not share the group"
assert_eq "$(group_order foot)" "$a $b $c" "the first three tabs stay in open order"

group_tab 1 foot
wait_until 3 '[ "$(active_tab_index foot)" = 0 ]' || fail "did not switch to the first tab"

open_window foot 4
d="$(active_address)"
wait_until 3 '[ "$(group_size foot)" = 4 ]' || fail "the fourth window did not join"
assert_eq "$(group_order foot)" "$a $b $c $d" "the new window is the last tab, not the one after the current"
assert_eq "$(active_address)" "$d" "the new window is still the active tab"
