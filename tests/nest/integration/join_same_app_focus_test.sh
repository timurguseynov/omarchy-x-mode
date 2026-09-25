#!/usr/bin/env bash
# Regression: a new window of the same app joined the group but did not become
# its active tab. It was added hidden (visible:false, acceptsInput:false) while
# the group stayed on the old tab, so a freshly opened dialog or login window
# appeared nowhere.
#
# The two windows share a class, so "the active window is a foot" proves
# nothing. The address does: the window that just opened has to be the one.
. "$(dirname "$0")/../../lib.sh"

open_window foot
first="$(active_address)"
assert_ne "$first" "" "the first window is active"

open_window foot 2

assert_eq "$(group_size foot)" 2 "the second foot joins the group"
assert_ne "$(active_address)" "$first" "the new window takes over, not the old tab"
assert_eq "$(active_class)" foot "the active window stays a foot"
assert_ge "$(visual_top foot)" "$(bar_top)" "the tabbar stays below the bar"
