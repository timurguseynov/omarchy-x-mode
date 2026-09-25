#!/usr/bin/env bash
# The dock comes up as a layer surface in the nest, vertically centred, and
# reserves nothing: it overlays windows, and the snap inset for it is a separate
# Hyprland-side value, so the top bar keeps its full width.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mh="${extent#*x}"

dock_start
dock_settle

read -r x y w h <<<"$(dock_box)"

# The card is iconSize + 2*pad wide, and the empty dock is one icon tall.
assert_eq "$w" 40 "the dock is one icon card wide"
assert_ge "$h" 40 "an empty dock still keeps a one-icon card"
assert_ge "$y" 1 "the dock is not glued to the top edge"
assert_le "$((y + h))" $((mh - 1)) "the dock is not glued to the bottom edge"

# Centred within a pixel or two.
centre=$((y + h / 2))
assert_between "$centre" $((mh / 2 - 3)) $((mh / 2 + 3)) "the dock is vertically centred"

assert_eq "$(bar_top)" 24 "the dock reserves nothing, so the bar keeps the top"

dock_stop
