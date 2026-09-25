#!/usr/bin/env bash
# Regression: the pack checked only Hyprland's internal fullscreen flag. A window
# the app itself put fullscreen (its own xdg fullscreen: a video player, a game,
# or an app that stays fullscreen after Cmd+F cleared the compositor's flag) was
# treated as a normal floating window, so the next re-clamp (push_bars_below on
# window.update_rules / window.active) pushed it below the top bar, and a
# screen-sized surface then hung off the bottom.
#
# Measured before the fix: the window moved from y=0 to y=54 on a 450x500 nest.
. "$(dirname "$0")/../../lib.sh"

open_window foot
# Let the open watch stop, so only the later re-clamp can move it.
sleep 2.2

# The app goes fullscreen on its own; the compositor stays out of it.
nest_ctl dispatch "hl.dsp.window.fullscreen_state({ internal = 0, client = 2, action = 'set', window = 'class:foot' })" >/dev/null
sleep 0.3

# Plant it at the screen top, where a normal window would be pushed below the bar.
nest_ctl dispatch "hl.dsp.window.move({ x = 0, y = 0, relative = false, window = 'class:foot' })" >/dev/null
sleep 0.3

# Any window opening re-evaluates the rules of every window, the re-clamp included.
open_window kitty
sleep 0.5

read -r x y _ _ _ <<<"$(win_geom foot)"
assert_eq "$x" 0 "a client-fullscreen window is not moved sideways"
assert_eq "$y" 0 "a client-fullscreen window is not pushed below the top bar"
