#!/usr/bin/env bash
# Regression: leaving fullscreen kept the fullscreen size and only moved the
# window down below the top bar. push_bars_below ran on window.update_rules
# while the window still carried the fullscreen box and its fullscreen flags
# were already clear; the move called moveTarget, which recorded that box as the
# floating one, so Hyprland's own restore on exit
# (CDefaultFloatingAlgorithm::recenter) handed the fullscreen box straight back.
#
# The window must come back to the exact floating box it had before fullscreen.
. "$(dirname "$0")/../../lib.sh"

open_window foot
# Let the open watch stop, so only the fullscreen transition can move it.
sleep 2.2

read -r x0 y0 w0 h0 _ <<<"$(win_geom foot)"

nest_ctl dispatch "hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set', window = 'class:foot' })" >/dev/null
sleep 0.4
nest_ctl dispatch "hl.dsp.window.fullscreen({ action = 'unset', window = 'class:foot' })" >/dev/null
sleep 0.6

read -r x y w h _ <<<"$(win_geom foot)"
assert_eq "$x" "$x0" "leaving fullscreen restores the floating x"
assert_eq "$y" "$y0" "leaving fullscreen restores the floating y"
assert_eq "$w" "$w0" "leaving fullscreen restores the floating width"
assert_eq "$h" "$h0" "leaving fullscreen restores the floating height"
