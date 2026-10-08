#!/usr/bin/env bash
# The menu's pin row remembers the class in the pinned file, which is how a
# pinned icon survives a restart. The row order below is the menu this test
# expects: New, a separator, the window row, a separator, Pin/Unpin, Quit.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
dock_settle

assert_eq "$(cat "$(dock_pinned_file)" 2>/dev/null || echo absent)" absent "nothing is pinned yet"

dock_menu_open 0

read -r rx ry <<<"$(dock_menu_row_point 0 4 "26 7 26 7 26 26")"
dock_menu_click "$rx" "$ry"
settle

assert_eq "$(python3 -c "import json;print(','.join(json.load(open('$(dock_pinned_file)'))))")" foot \
  "the pin row writes the class to the pinned file"

# The pinned file is what a restart reads, so it has to be there on disk. The
# card stays one icon tall: the pinned app is the running one, so there is no
# second section.
assert_eq "$(dock_box | awk '{print $4}')" 40 "one pinned running app is a one-icon card"

# The same row now reads Unpin. Clicking it clears the file again.
dock_menu_open 0
read -r rx ry <<<"$(dock_menu_row_point 0 4 "26 7 26 7 26 26")"
dock_menu_click "$rx" "$ry"
settle

assert_eq "$(python3 -c "import json;print(','.join(json.load(open('$(dock_pinned_file)'))))")" "" \
  "the same row unpins"

dock_stop
