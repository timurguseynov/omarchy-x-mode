#!/usr/bin/env bash
# Regression: dragging a window to the top let its chrome climb over the bar. The
# clamp has to hold the chrome at the reserved top, whether or not the drag ends
# in a zone: here the drag ends in the maximize band, so the window fills the
# workarea and its titlebar still starts below the bar.
. "$(dirname "$0")/../../lib.sh"

open_window foot

extent="$(pointer_extent)"
mw="${extent%x*}"
drag_to foot $((mw / 2)) 2

read -r _ y _ _ _ <<<"$(win_geom foot)"
assert_ge "$(visual_top foot)" "$(bar_top)" "the titlebar stays below the bar after dragging up"
assert_ge "$y" "$(bar_top)" "the window box stays below the bar"
