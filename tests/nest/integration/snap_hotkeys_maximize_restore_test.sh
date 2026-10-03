#!/usr/bin/env bash
# Super+Alt+F maximizes to the workarea, and Ctrl+Alt+Down puts back the geometry
# the window had before, so the two keys are a pair rather than a one-way trip.
#
# Every step waits for the box it is about instead of sleeping a fixed 0.4s. A
# restore sends a resize and a move, and under a full suite (five nests) the
# client's answer to the resize can land after the read: the run then says the
# width was not restored while x and y -- the move -- already were, which is a
# property of the read, not of the restore.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"
minw=$((mw * 8 / 10))

open_window foot
key super+alt+left
wait_still foot
read -r bx by bw bh _ <<<"$(win_geom foot)"

key super+alt+f
wait_until 5 '[ "$(win_geom foot | cut -d" " -f3)" -ge "$minw" ]' \
  || fail "Super+Alt+F did not fill the workarea (at $(win_geom foot))"
read -r _ _ xw _ _ <<<"$(win_geom foot)"
assert_ge "$xw" "$minw" "Super+Alt+F fills the workarea"

want="$bx $by $bw $bh"
key ctrl+alt+down
wait_until 5 '[ "$(win_geom foot | cut -d" " -f1-4)" = "$want" ]' \
  || fail "Ctrl+Alt+Down left the window at $(win_geom foot), wanted $want"
read -r rx ry rw rh _ <<<"$(win_geom foot)"
assert_eq "$rx" "$bx" "Ctrl+Alt+Down restores the x the window had"
assert_eq "$ry" "$by" "Ctrl+Alt+Down restores the y the window had"
assert_eq "$rw" "$bw" "Ctrl+Alt+Down restores the width the window had"
assert_eq "$rh" "$bh" "Ctrl+Alt+Down restores the height the window had"
