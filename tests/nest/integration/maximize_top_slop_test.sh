#!/usr/bin/env bash
# The maximize band is the reserved top plus a small slop (8px by default). A
# drop above that line maximizes; a drop just below it snaps to nothing, so the
# window stays the size it had.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"

open_window foot

drag_to foot $((mw / 2)) 28
read -r _ _ w1 _ _ <<<"$(win_geom foot)"
assert_ge "$w1" $((mw * 8 / 10)) "a drop inside the top band maximizes"

# A plain half first, so the next drop is measured against a real size.
snap foot left
read -r _ _ w2 _ _ <<<"$(win_geom foot)"

drag_to foot $((mw / 2)) 44
read -r _ _ w3 _ _ <<<"$(win_geom foot)"
assert_eq "$w3" "$w2" "a drop below the slop must not maximize"
