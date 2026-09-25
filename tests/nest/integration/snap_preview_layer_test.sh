#!/usr/bin/env bash
# The snap preview is a Quickshell layer that follows the cursor while a window is
# dragged, so it can be seen as a layer instead of guessed at from pixels: it is
# there while the cursor is in a zone and gone when it leaves.
#
# The shell that draws it is the dock's, which instantiates SnapPreview and the
# switcher as well, and it is told what to show through a file in the nest's
# runtime directory.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"
mh="${extent#*x}"

open_window foot

dock_start
dock_settle

assert_eq "$(dock_layer_box omarchy-snap-preview 2>/dev/null || echo none)" none \
  "no preview while nothing is being dragged"

read -r tx ty <<<"$(titlebar_point foot)"

pointer_begin
pointer_do "move $tx $ty"
pointer_do "press left"
pointer_do "move $((tx - 30)) $((ty + 30))"
pointer_do "move 6 $((mh / 2))"
sleep 0.6

w="$(dock_layer_box omarchy-snap-preview | awk '{print $3}')"
assert_ge "$w" 20 "the preview layer is up while the cursor is in a zone"

pointer_do "move $((mw / 2)) $((mh / 3))"
sleep 0.5
assert_eq "$(dock_layer_box omarchy-snap-preview 2>/dev/null || echo none)" none \
  "the preview goes away when the cursor leaves the zone"

pointer_do "release left"
pointer_end

dock_stop
