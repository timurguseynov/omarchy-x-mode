#!/usr/bin/env bash
# Clicking a dock icon focuses and raises that app. The dock lists one icon per
# class, sorted, with the pinned ones first, so the icon for kitty is the one
# after foot.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window kitty
dock_settle

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
assert_eq "$(active_class)" foot "foot is focused to begin with"

read -r px py <<<"$(dock_icon_point 1)"
pointer_click "$px" "$py"
sleep 0.5

assert_eq "$(active_class)" kitty "clicking an icon focuses that app"
assert_eq "$(topmost)" kitty "clicking an icon raises that app"

dock_stop
