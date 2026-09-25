#!/usr/bin/env bash
# Two bindings maximize: Super+Alt+F and Ctrl+Alt+Up. Both have to land on the
# same geometry, or one of them is computing the workarea differently.
. "$(dirname "$0")/../../lib.sh"

open_window foot

key super+alt+f
sleep 0.4
read -r fx fy fw fh _ <<<"$(win_geom foot)"

key ctrl+alt+down
sleep 0.4
key ctrl+alt+up
sleep 0.4
read -r cx cy cw ch _ <<<"$(win_geom foot)"

assert_eq "$cx" "$fx" "Ctrl+Alt+Up maximizes to the same x"
assert_eq "$cy" "$fy" "Ctrl+Alt+Up maximizes to the same y"
assert_eq "$cw" "$fw" "Ctrl+Alt+Up maximizes to the same width"
assert_eq "$ch" "$fh" "Ctrl+Alt+Up maximizes to the same height"
