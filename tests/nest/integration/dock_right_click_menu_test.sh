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
# An empty dock is the same 40px as a dock with one icon, so the settle above
# can return before foot's icon is in the card. One click then hits nothing.
# Click again until the menu layer is actually up.
menu_open() {
  local w
  w="$(dock_layer_box x-mode-dock-menu 2>/dev/null | awk '{print $3}')"
  [ -n "$w" ] && [ "$w" -ge 100 ]
}
for _ in $(seq 1 16); do
  pointer_click "$px" "$py" right
  sleep 0.25
  menu_open && break
done

w="$(dock_layer_box x-mode-dock-menu 2>/dev/null | awk '{print $3}')"
assert_ge "${w:-0}" 100 "right-clicking an icon opens the context menu layer"

dock_stop
