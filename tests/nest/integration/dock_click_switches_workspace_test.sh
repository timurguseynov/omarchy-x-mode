#!/usr/bin/env bash
# A click on an icon whose app lives on another workspace moves to that
# workspace and focuses the window, instead of being ignored as "already
# focused". The dock used to skip a class whose window had focusHistoryID 0,
# which is true for a window on a workspace that is not being viewed.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window kitty
dock_settle

nest_ctl dispatch "hl.dsp.window.move({ workspace = \"2\", window = 'class:kitty' })" >/dev/null
sleep 0.3
nest_ctl dispatch "hl.dsp.focus({ workspace = \"1\" })" >/dev/null
sleep 0.3
assert_eq "$(viewed_workspace)" 1 "the test starts on workspace 1"

read -r px py <<<"$(dock_icon_point 1)"
pointer_click "$px" "$py"
sleep 0.6

assert_eq "$(viewed_workspace)" 2 "clicking the icon switches to the app's workspace"
assert_eq "$(active_class)" kitty "clicking the icon focuses the window there"

dock_stop
