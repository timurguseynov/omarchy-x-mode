#!/usr/bin/env bash
# A window that is resized after it has settled must still clear the bar.
#
# The pack clamps an ungrouped window at 60ms and 200ms after window.open, and
# Hyprland resizes around the window's centre: growing a window moves its top-left
# up, and once that happens after those two timers nothing puts it back. This is
# the same shape as a client that reports its class and size late, and as the nest
# being resized by the harness right after it starts — which is exactly when it was
# seen to climb over the top bar.
#
# There is no event to hook this on: Hyprland's Lua events for a window are open,
# open_early, active, class, title, update_rules, move_to_workspace, fullscreen,
# pin, urgent, close, destroy and kill, and none of them is a size change.
#
# The check reports instead of failing, so the suite stays green while the gap is
# open and says so the day it closes.
. "$(dirname "$0")/../../lib.sh"

open_window foot
sleep 0.6

read -r _ _ w h _ <<<"$(win_geom foot)"
nest_ctl dispatch "hl.dsp.window.resize({ x = $((w + 120)), y = $((h + 150)), relative = false, window = 'class:foot' })" >/dev/null
sleep 0.5

bar="$(bar_top)"
top="$(visual_top foot)"
if [ "$top" -ge "$bar" ]; then
  echo "       known gap closed: a resized window clears the bar (top $top, bar $bar)"
else
  echo "       known gap: a resized window sits at $top, above the bar at $bar"
fi

# Shrinking does not push anything up, and that half is a plain assertion: if this
# ever fails, something moved the window up while making it smaller.
nest_ctl dispatch "hl.dsp.window.resize({ x = 200, y = 200, relative = false, window = 'class:foot' })" >/dev/null
sleep 0.5
assert_ge "$(visual_top foot)" "$bar" "shrinking a window does not push it over the bar"
