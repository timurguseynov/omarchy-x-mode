#!/usr/bin/env bash
# Ctrl+Alt+Down puts back the box the window had before the pack moved it, and a
# reload must not lose that box: a theme switch, the panel's toggles and an
# install all reload the config, and the window itself has not moved. The restore
# point lived only in the parse, so after a reload the key placed the default box
# instead of the one the window had.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"

open_window foot
key super+alt+left
wait_still foot
read -r bx by bw bh _ <<<"$(win_geom foot)"

key super+alt+f
wait_until 5 '[ "$(win_geom foot | cut -d" " -f3)" -ge '"$((mw * 8 / 10))" ]' \
  || fail "Super+Alt+F did not fill the workarea (at $(win_geom foot))"

nest_ctl reload >/dev/null
wait_until 5 '[ "$(win_geom foot | cut -d" " -f3)" -ge '"$((mw * 8 / 10))" ]' \
  || fail "the reload did not leave the maximized box (at $(win_geom foot))"

want="$bx $by $bw $bh"
key ctrl+alt+down
wait_until 5 '[ "$(win_geom foot | cut -d" " -f1-4)" = "$want" ]' \
  || fail "Ctrl+Alt+Down after a reload left the window at $(win_geom foot), wanted $want"
read -r rx ry rw rh _ <<<"$(win_geom foot)"
assert_eq "$rx" "$bx" "the x survives a reload"
assert_eq "$ry" "$by" "the y survives a reload"
assert_eq "$rw" "$bw" "the width survives a reload"
assert_eq "$rh" "$bh" "the height survives a reload"
