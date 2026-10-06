#!/usr/bin/env bash
# The panel's rows in an app's card write the settings file and then call
# x_mode.refresh_apps_off() -- not a reload. So that call has to re-plan what a
# flag decides, or pinning a flag for one app writes the file and does nothing
# until some other click happens to reload the config: "Ctrl+1..0 switches tabs"
# pinned for one app only started working after the desktop-wide row was toggled,
# which reloads.
#
# The pin is also per app: the handler has to let the key through for an app that
# has no pin, even while the binds exist for another one.
. "$(dirname "$0")/../../lib.sh"

panel_wrote() { # JSON
  printf '%s\n' "$1" > "$NEST_SETTINGS"
  # Exactly what the panel does after writing an app's flag.
  nest_ctl eval 'if x_mode and x_mode.refresh_apps_off then x_mode.refresh_apps_off() end' >/dev/null
}

# Start from a clean parse: what the flags were in this slot's last scenario is
# not this scenario's business (the file the panel writes does not reload the
# config on its own, so a reload is what makes the state known).
printf '%s\n' '{"options":{"keys":{}},"apps":{}}' > "$NEST_SETTINGS"
nest_ctl reload >/dev/null
wait_until 5 '[ "$(bind_count_desc "Switch to tab 1" 4)" = 0 ]' \
  || fail "Ctrl+1 is still bound after a clean reload"

# Only the app's own pin, written the way the panel writes it: the desktop-wide
# flag stays off, so a bind that exists at all exists because of this app. The
# file alone changes nothing -- the pack has not read it -- which is the point of
# the call below.
panel_wrote '{"options":{"keys":{}},"apps":{"foot":{"chrome":true,"ctrlTabSwitch":true}}}'
assert_ge "$(bind_count_desc 'Switch to tab 1' 4)" 1 "a per-app pin puts Ctrl+1 in place, without a reload"
assert_ge "$(bind_count_desc 'Switch to tab 9' 4)" 1 "and Ctrl+9 with it"

open_window foot
open_window foot
wait_until 5 '[ "$(group_size foot)" = 2 ]' || fail "the two foot windows did not become one group"

# The handler asks Hyprland which window is focused, so the press is made with
# that window focused (the same shape ctrl_tab_switch_behavior_test uses).
focus_foot() { nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null; sleep 0.3; }
focus_foot

# Ctrl+2 is the second tab, and the index is the tab's position in the group
# (0-based), so a switch to the second tab reads as 1.
key ctrl+2
wait_until 3 '[ "$(active_tab_index foot)" = 1 ]' || fail "the pinned app's Ctrl+2 did not switch its tab"

# The pin is this app's: with it moved to another class, the binds are still there
# (that class wants them) and Ctrl+1 in foot has to reach foot, not the pack. The
# second tab is made current here by Hyprland's own dispatch, not by the pack, so
# the press below is the only thing that could change it -- focusing by class
# would make the group's first tab current by itself.
panel_wrote '{"options":{"keys":{}},"apps":{"kitty":{"chrome":true,"ctrlTabSwitch":true}}}'
nest_ctl eval "local w = hl.get_active_window(); hl.dispatch(hl.dsp.group.active({ index = 2, window = w }))" >/dev/null
wait_until 3 '[ "$(active_tab_index foot)" = 1 ]' || fail "the second tab could not be made current"
key ctrl+1
sleep 0.4
assert_eq "$(active_tab_index foot)" 1 "an app without the pin keeps its tab and gets the key"
