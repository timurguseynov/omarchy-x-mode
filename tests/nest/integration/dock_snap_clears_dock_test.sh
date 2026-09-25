#!/usr/bin/env bash
# The dock overlays windows instead of reserving space, so the snap geometry has
# to keep clear of it on its own. A window snapped to the right must stop before
# the dock's left edge, not under it.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
snap foot right
dock_settle

read -r dock_x _ _ _ <<<"$(dock_box)"
read -r x _ w _ _ <<<"$(win_geom foot)"

assert_le $((x + w)) "$dock_x" "a right-snapped window stops before the dock"

dock_stop
