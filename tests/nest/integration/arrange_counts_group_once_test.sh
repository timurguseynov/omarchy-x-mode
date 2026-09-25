#!/usr/bin/env bash
# The arrange deals one window per class, and same-app windows are already one
# group, so a group of two tabs takes one half rather than two. Both tabs have to
# still be there afterwards.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"
half=$((mw / 2))

open_window foot
open_window foot 2
open_window kitty
assert_eq "$(group_size foot)" 2 "two windows share the group"

touch "$NEST_STATE/state/arrange"
nest_ctl reload >/dev/null
sleep 1.0

read -r fx _ fw _ _ <<<"$(visible_geom foot)"
read -r kx _ kw _ _ <<<"$(visible_geom kitty)"

assert_le "$fw" $((half + 40)) "the group takes one half, not two"
assert_le "$kw" $((half + 40)) "the other app takes a half"
assert_ne "$fx" "$kx" "the two land on different sides"
assert_eq "$(count_class foot)" 2 "both tabs survive the arrange"
