#!/usr/bin/env bash
# A right-click on an icon opens the context menu, which is its own layer (an
# overlay), so it can be seen as a layer and not guessed at.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
dock_settle

assert_eq "$(dock_layer_box x-mode-dock-menu 2>/dev/null || echo none)" none \
  "the menu layer is not there before the click"

read -r px py <<<"$(dock_icon_point 0)"
pointer_click "$px" "$py" right
sleep 0.6

w="$(dock_layer_box x-mode-dock-menu | awk '{print $3}')"
assert_ge "$w" 100 "right-clicking an icon opens the context menu layer"

dock_stop
