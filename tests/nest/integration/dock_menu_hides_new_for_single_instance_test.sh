#!/usr/bin/env bash
# An app whose desktop entry declares itself single-instance gets no "New" row:
# starting a second copy would not work anyway. The dock reads the entries in its
# own HOME, so the entry is written there and stays out of the real system.
#
# Without the New row the menu is: the window, a separator, Pin, Quit -- so row 3
# is Quit and clicking it closes the app. With a New row row 3 would be a window
# row or a separator, and nothing would close.
. "$(dirname "$0")/../../lib.sh"

entry="$NEST_STATE/home/.local/share/applications/foot.desktop"
mkdir -p "$(dirname "$entry")"
cat > "$entry" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Foot
Exec=foot
Icon=foot
SingleMainWindow=true
DESKTOP

dock_start
open_window foot
dock_settle

read -r px py <<<"$(dock_icon_point 0)"
pointer_click "$px" "$py" right
sleep 0.6

read -r rx ry <<<"$(dock_menu_row_point 0 3 "26 7 26 26")"
pointer_click "$rx" "$ry"
sleep 0.8

assert_eq "$(count_class foot)" 0 "a single-instance app has no New row, so that row is Quit"

dock_stop
