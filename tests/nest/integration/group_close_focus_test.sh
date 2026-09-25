#!/usr/bin/env bash
# Regression: closing the active tab of a group handed focus to an unrelated
# app. Symptom: after closing a terminal, activewindow became
# org.gitfourchette.gitfourchette while other foot windows were still in the
# group, so the group was left behind.
#
# A foreign window is opened on purpose: without one, focus could stay on the
# group by accident and the test would pass either way.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
open_window foot 3
assert_eq "$(group_size foot)" 3 "three same-app windows share one group"

open_window kitty

focus() { nest_ctl dispatch "hl.dsp.focus({ window = 'class:$1' })" >/dev/null; sleep 0.2; }
close_active() {
  # hyprctl dispatch takes a dispatcher object here, not the legacy 'killactive'
  # string, so close the active window by address the way nest_clean does.
  local addr
  addr="$(nest_ctl activewindow -j | python3 -c "import json,sys;print((json.load(sys.stdin) or {}).get('address') or '')")"
  assert_ne "$addr" "" "there is an active window to close"
  nest_ctl dispatch "hl.dsp.window.close({ window = 'address:$addr' })" >/dev/null
}

focus foot
assert_eq "$(active_class)" foot "the group is focused before closing"

close_active
sleep 0.4

assert_eq "$(active_class)" foot "focus stays in the group after the active tab closes"
assert_eq "$(group_size foot)" 2 "the group keeps its remaining windows"
assert_eq "$(topmost)" foot "the group is raised after a tab closes"
assert_ge "$(visual_top foot)" "$(bar_top)" "the tabbar stays below the bar"
