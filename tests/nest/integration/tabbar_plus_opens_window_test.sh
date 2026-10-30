#!/usr/bin/env bash
# The + slot on the tabbar opens another window of the same app, and that window
# joins the group. Its x is the last 34px of the tabbar. Launch is the dock's
# (command file / xmodelaunch), so the dock has to be up.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window foot 2
assert_eq "$(group_size foot)" 2 "two windows share the group"

read -r px py <<<"$(plus_point foot)"
pointer_click "$px" "$py"

# The launch goes through gtk-launch, which is slow on a cold start -- and slower
# still with five nests running: thirty seconds, because a failed spawn is a
# spawn that never happens and ten seconds was the whole budget.
wait_for_count foot 3 30

assert_eq "$(count_class foot)" 3 "the + slot opens another window of the app"
assert_eq "$(group_size foot)" 3 "the new window joins the group"
