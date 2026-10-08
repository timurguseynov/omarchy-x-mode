#!/usr/bin/env bash
# Alt+Tab is the focused app's ring on the workspace the user is looking at:
# another app's window is not in it, and neither is a window of another
# workspace, even when it was the last thing used. The key that walks tab by tab
# must not move the whole desktop.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
open_window kitty
open_command xmode-extra foot --app-id=xmode-extra

nest_ctl dispatch "hl.dsp.focus({ window = 'class:xmode-extra' })" >/dev/null
sleep 0.3
nest_ctl dispatch "hl.dsp.window.move({ workspace = \"2\", window = 'class:xmode-extra' })" >/dev/null
sleep 0.4
nest_ctl dispatch "hl.dsp.focus({ workspace = \"1\" })" >/dev/null
sleep 0.3
# group.active only moves the tab when the group holds the focus, so put the
# focus in the group first.
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
group_tab 1 foot
assert_eq "$(viewed_workspace)" 1 "the test works on workspace 1"
assert_eq "$(active_class)" foot "foot is focused"

key alt+tab
settle
assert_eq "$(active_class)" foot "the first step is the group's next tab"
assert_eq "$(active_tab_index foot)" 1 "which is the second tab"

key alt+tab
settle
assert_eq "$(active_class)" foot "the ring stays in the app on the viewed workspace"
assert_eq "$(active_tab_index foot)" 0 "so it wraps to the first tab"
assert_eq "$(viewed_workspace)" 1 "and the workspace never changed"
