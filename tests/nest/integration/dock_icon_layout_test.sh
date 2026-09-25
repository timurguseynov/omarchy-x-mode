#!/usr/bin/env bash
# The card is iconSize + 2*pad wide, and each icon adds iconSize + spacing to its
# height, so two icons make 26*2 + 6 + 14. This is the arithmetic
# dock_icon_point() relies on, so it is worth pinning directly: if it drifts, the
# clicks in the other dock tests land on the wrong icon or on nothing.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window kitty
dock_settle

read -r x y w h <<<"$(dock_box)"
assert_eq "$w" 40 "the card is iconSize + 2*pad wide"
assert_eq "$h" 72 "two icons, the gap between them and the padding"

# Every icon's point has to land inside the card.
for i in 0 1; do
  read -r px py <<<"$(dock_icon_point "$i")"
  assert_between "$px" "$x" $((x + w)) "icon $i's x is inside the card"
  assert_between "$py" "$y" $((y + h)) "icon $i's y is inside the card"
done

dock_stop
