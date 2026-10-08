#!/usr/bin/env bash
# Autosnap on install: install.sh drops the arrange marker before its reload, and
# the already-open windows are dealt once into left/right halves, one per app.
# The marker is removed on sight, so a plain reload afterwards has to leave the
# windows where they are. The bug was windows staying stacked on top of each
# other, and a later reload re-shuffling them.
#
# The marker is a file in the state dir; its content is not read.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"
half=$((mw / 2))

open_window foot
open_window kitty

touch "$NEST_STATE/state/arrange"
nest_ctl reload >/dev/null
# The pack removes the marker once the windows have actually been dealt, so that is
# the wait; a clock here read a mid-pass frame and called it a half.
wait_until 8 '[ ! -e "$NEST_STATE/state/arrange" ]' || fail "the arrange never dealt the windows"

read -r fx fy fw _ _ <<<"$(win_geom foot)"
read -r kx ky kw _ _ <<<"$(win_geom kitty)"

assert_ge "$fy" 64 "an arranged window keeps the gap under the bar"
assert_ge "$ky" 64 "an arranged window keeps the gap under the bar"
assert_ge "$(visual_top foot)" 36 "the arranged window clears the bar"
assert_ge "$(visual_top kitty)" 36 "the arranged window clears the bar"
assert_le "$fw" $((half + 40)) "each app gets a half, not the full width"
assert_le "$kw" $((half + 40)) "each app gets a half, not the full width"
assert_ne "$fx" "$kx" "the two apps land on different sides"

nest_ctl reload >/dev/null
# Nothing to wait *for* here: the assertion is that this reload does nothing at
# all, and the only way to see "nothing" is to give the pass it would have started
# the time it would have taken. 1s is past the arrange timer (600ms), and the
# marker the pack drops the request with is not there to watch.
sleep 1.0

read -r fx2 fy2 _ _ _ <<<"$(win_geom foot)"
assert_eq "$fx2" "$fx" "a plain reload must not re-arrange the windows"
assert_eq "$fy2" "$fy" "a plain reload must not re-arrange the windows"
