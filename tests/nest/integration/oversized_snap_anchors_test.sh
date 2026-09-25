#!/usr/bin/env bash
# A window whose client minimum is wider than the snap zone used to be snapped
# with its left edge off-screen: the zone asks for a size below the minimum, so
# Hyprland grows the box around its centre (kdenlive was observed at x=-43 on a
# 1920 monitor, a 1027-wide window on a 938-wide half). The pack now grows the
# snap target to the minimum and keeps the snapped edge put, so the window
# overhangs the far side of the zone.
#
# A min_size rule stands in for the client hint: it feeds CWindow::minSize(),
# which Snap::contentBox reads, and clampWindowSize grows around the centre the
# same way a late client commit does.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"
mh="${extent#*x}"
minw=$((mw * 2 / 3))
minh=$((mh / 2))

open_window foot
# Let the open watch stop, so this is only about the snap.
sleep 2.2

nest_ctl eval "hl.window_rule({ name = 'oversized-snap', match = { class = 'foot' }, min_size = '${minw} ${minh}' })" >/dev/null
sleep 0.5

snap foot left

read -r x _ w _ _ <<<"$(win_geom foot)"
assert_ge "$x" 0 "the snapped window must not hang off the left edge"
assert_ge "$w" "$minw" "the window keeps its minimum width"
assert_ge "$((x + w))" "$((mw / 2))" "the window overhangs the zone, not the screen"
