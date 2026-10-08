#!/usr/bin/env bash
# Pinning a running app has to rebuild the card on that click: the icon moves
# into the pinned section, a separator appears, and the dock has to keep
# answering. The pin-file test only has one icon, so the card height does not
# change and a dock that froze on Pin still looks fine.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window kitty
dock_settle

assert_eq "$(dock_box | awk '{print $4}')" 72 "two running apps, no pins"

# Icon 1 is kitty (foot sorts first). Pin it.
dock_menu_open 1

read -r rx ry <<<"$(dock_menu_row_point 1 4 "26 7 26 7 26 26")"
dock_menu_click "$rx" "$ry"

# Pin has to rebuild on that click. Wait for the file the row writes first:
# under a loaded host the click can take a moment to land, and that delay is not
# what the scenario is about. From the write on, only a short wait counts -- the
# 3s client reconcile would also move the icon, so a card still at 72 after that
# is a Pin that did not rebuild, which is the bug this pins down.
wait_until 8 '[ -s "$(dock_pinned_file)" ] && grep -q kitty "$(dock_pinned_file)"'
h="$(dock_box | awk '{print $4}')"
for _ in $(seq 1 8); do
  [ "$h" = 79 ] && break
  sleep 0.2
  h="$(dock_box | awk '{print $4}')"
done

assert_eq "$(python3 -c "import json;print(','.join(json.load(open('$(dock_pinned_file)'))))")" kitty \
  "the pin row writes kitty"

# The rebuild is the point: pinned kitty + running foot is a two-section card
# (26 + 6 + 1 + 6 + 26 of icons, plus 14 of padding).
assert_eq "$h" 79 "pinning a running app grows the separator"

assert_eq "$(dock_layer_box x-mode-dock-menu 2>/dev/null || echo none)" none \
  "the menu closes after Pin"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
assert_eq "$(active_class)" foot "foot is focused to begin with"

read -r px py <<<"$(dock_icon_point 0)"
pointer_click "$px" "$py"
settle
assert_eq "$(active_class)" kitty "the first icon is the app that was just pinned"

# A dock that froze on Pin would not map the menu again.
dock_menu_open 0
w="$(dock_layer_box x-mode-dock-menu 2>/dev/null | awk '{print $3}')"
assert_ge "${w:-0}" 100 "the dock still opens a menu after a pin"

dock_stop
