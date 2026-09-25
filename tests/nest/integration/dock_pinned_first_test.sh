#!/usr/bin/env bash
# A pinned app comes before the running ones, so with kitty pinned the first icon
# is kitty even though foot sorts before it alphabetically.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window kitty
dock_settle
dock_pin '["kitty"]'

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
assert_eq "$(active_class)" foot "foot is focused to begin with"

read -r px py <<<"$(dock_icon_point 0)"
pointer_click "$px" "$py"
sleep 0.5

assert_eq "$(active_class)" kitty "the first icon is the pinned app"

dock_stop
