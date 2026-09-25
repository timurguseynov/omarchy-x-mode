#!/usr/bin/env bash
# Dragging a pinned icon past its neighbour rewrites the pinned order, which is
# what makes a Mac-style dock reorder stick. Both apps are pinned and running, so
# the column is one block of two icons and neither a separator nor a running
# section shifts the positions.
. "$(dirname "$0")/../../lib.sh"

# Pinned before the dock starts: its pinned list is a FileView, and a file
# created while it runs is not picked up until the view is reloaded.
dock_pin '["foot","kitty"]'
dock_start
open_window foot
open_window kitty
dock_settle

before="$(python3 -c "import json;print(','.join(json.load(open('$(dock_pinned_file)'))))")"
assert_eq "$before" foot,kitty "the pinned order starts as written"

read -r x1 y1 <<<"$(dock_icon_point 0)"
read -r x2 y2 <<<"$(dock_icon_point 1)"

pointer_drag "$x1" "$y1" "$x2" "$y2"
sleep 0.8

after="$(python3 -c "import json;print(','.join(json.load(open('$(dock_pinned_file)'))))")"
assert_eq "$after" kitty,foot "dragging the first icon past the second swaps them"

dock_stop
