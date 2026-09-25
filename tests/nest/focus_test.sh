#!/usr/bin/env bash
# Focusing a window raises it: the focused window must end up last in the
# clients list (that is z-order, topmost last).
#
# Regression test for two things: 1e4b74c re-read the live active window when
# the deferred raise ran, so a window that took focus while another was becoming
# active could raise the wrong one; and a raise_pending that never cleared (an
# error on a window that closed in the 1ms window) swallowed every later raise,
# leaving the focused window behind the app in front.
. "$(dirname "$0")/../lib.sh"

topmost() {
  nest_ctl clients -j | python3 -c "
import json, sys
ws = [c for c in json.load(sys.stdin) if c['mapped'] and not c['hidden']]
print(ws[-1]['class'] if ws else '')"
}

focus() { nest_ctl dispatch "hl.dsp.focus({ window = 'class:$1' })" >/dev/null; sleep 0.15; }

open_window foot
open_window kitty

for _ in 1 2 3; do
  focus foot
  assert_eq "$(topmost)" foot "the focused window must be on top"
  focus kitty
  assert_eq "$(topmost)" kitty "the focused window must be on top"
done

# A same-app window joins the group and becomes its current tab (the shape of a
# push dialog opening over the main window). The group must stay on top, and the
# tabbar must stay below the bar.
open_window foot 2
sleep 0.3
focus foot
assert_eq "$(topmost)" foot "the group stays on top after a window joins it"
assert_ge "$(visual_top foot)" 36 "the group's tabbar stays below the bar"
