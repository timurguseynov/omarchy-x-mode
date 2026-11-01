#!/usr/bin/env bash
# The dock belongs to the pack's workspaces. A layer surface belongs to the
# monitor, not to a workspace, so what a mode switch changes is whether the dock
# shows itself: the pack publishes the active workspace's mode, and the dock hides
# on everything that is not xmode.
. "$(dirname "$0")/../../lib.sh"

MODE_FILE="$NEST_RUNTIME/omarchy-x-mode.workspace"

# The dock's own layer: its namespace is the shell plugin's.
dock_visible() { [ -n "$(dock_layer_box x-mode-dock 2>/dev/null)" ]; }
gone() { [ -z "$(dock_layer_box x-mode-dock 2>/dev/null)" ]; }

dock_start
# The dock is up while the workspace is the pack's.
nest_ctl eval 'o.workspace_mode({ workspace = "1", mode = "xmode" })' >/dev/null
wait_until 5 'dock_visible' || fail "the dock is not shown on an xmode workspace"
assert_eq "$(cat "$MODE_FILE" 2>/dev/null | awk '{print $2}')" xmode \
  "the pack publishes the active workspace's mode"

# A tiling workspace is Omarchy's: no dock there.
nest_ctl eval 'o.workspace_mode({ workspace = "1", mode = "dwindle" })' >/dev/null
wait_until 10 'gone' || fail "the dock is still shown on a dwindle workspace (mode file: $(cat "$MODE_FILE" 2>/dev/null))"
assert_eq "$(cat "$MODE_FILE" 2>/dev/null | awk '{print $2}')" dwindle \
  "the published mode follows the switch"

# And back.
nest_ctl eval 'o.workspace_mode({ workspace = "1", mode = "xmode" })' >/dev/null
wait_until 10 'dock_visible' || fail "the dock did not come back on xmode"

# The mode is the last field of the line, and only it decides: an id that came out
# as something odd -- the workspace object handing out a table, printed as
# "table: 0x55a2..." -- hid the dock for a whole session until a workspace switch
# rewrote the file, which is what a dock that had "crashed" looked like.
printf 'table: 0x55a204dd5040 xmode\n' > "$MODE_FILE"
wait_until 5 'dock_visible' || fail "an odd id in the published line hid the dock"

dock_stop
