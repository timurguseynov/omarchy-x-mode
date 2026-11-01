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
settle
# Both keys below go through hl.get_active_window(): with nothing focused they
# are silent no-ops, and the assertion that follows would blame the maximize key
# for a nest where no window had the focus at all.
assert_eq "$(active_class)" foot "the new window took the focus"
key super+alt+left
wait_still foot
read -r bx by bw bh _ <<<"$(win_geom foot)"

key super+alt+f
if ! wait_until 5 '[ "$(win_geom foot | cut -d" " -f3)" -ge "$minw" ]'; then
  # Say what the nest looked like instead of only that the box did not grow: a
  # lost key, a plugin that is not loaded and a pack that never bound the key all
  # read the same in the assertion below.
  {
    echo "  diag: geometry $(win_geom foot)"
    echo "  diag: plugins $(nest_ctl plugin list 2>&1 | tr '\n' ' ' | cut -c1-200)"
    echo "  diag: pack loaded $(nest_ctl eval 'return tostring(x_mode ~= nil)' 2>&1)"
    echo "  diag: binds $(nest_ctl binds -j 2>/dev/null | python3 -c "import json,sys;print([(b.get('description'),b.get('modmask'),b.get('dispatcher')) for b in json.load(sys.stdin) if b.get('key')=='F'])" 2>&1)"
    echo "  diag: active '$(active_class)' $(nest_ctl active address 2>&1)"
    echo "  diag: foot windows $(nest_ctl clients -j 2>/dev/null | python3 -c "import json,sys;print([(c['address'],c['at'],c['size'],c['mapped'],c['hidden'],len(c.get('grouped') or [])) for c in json.load(sys.stdin) if c['class']=='foot'])" 2>&1)"
  } >&2
  fail "Super+Alt+F did not fill the workarea (at $(win_geom foot))"
fi
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
