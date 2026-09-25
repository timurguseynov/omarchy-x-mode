#!/usr/bin/env bash
# The + slot on the tabbar opens another window of the same app, and that window
# joins the group. Its x is the last 34px of the tabbar.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
assert_eq "$(group_size foot)" 2 "two windows share the group"

read -r px py <<<"$(plus_point foot)"
pointer_click "$px" "$py"

for _ in $(seq 1 40); do
  [ "$(count_class foot)" -ge 3 ] && break
  sleep 0.1
done

assert_eq "$(count_class foot)" 3 "the + slot opens another window of the app"
sleep 0.4
assert_eq "$(group_size foot)" 3 "the new window joins the group"
