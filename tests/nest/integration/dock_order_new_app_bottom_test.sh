#!/usr/bin/env bash
# The unpinned column is in launch order, newest at the bottom, not sorted by
# class. Opening kitty, foot and dockz is the reverse of what the class sort
# gives (dockz foot kitty), so the order the card reports says which order it is
# using, and no icon of the three is pinned.
#
# The dock remembers that order in its own HOME (the nest's), next to the pin
# list, so a class that quits drops out of it: launching the app again counts as
# new and lands at the bottom instead of back in its old slot. That is the part
# a remembered slot per class would get wrong, so it is checked here too.
. "$(dirname "$0")/../../lib.sh"

# The remembered launch order, as one line.
dock_state_order() {
  python3 - "$NEST_STATE/home/.config/omarchy/x-mode-dock-order.json" <<'PY'
import json, sys
try:
    print(" ".join(json.load(open(sys.argv[1]))))
except Exception:
    print("")
PY
}

close_class() { # CLASS
  nest_ctl dispatch "hl.dsp.window.close({ window = 'class:$1' })" >/dev/null
}

dock_start
open_window kitty
dock_wait_order "kitty" || fail "the first app did not reach the card: '$(dock_order)'"

open_window foot
dock_wait_order "kitty foot" || fail "a new app must go to the bottom, not into the sort: '$(dock_order)'"

# A third class from foot --app-id=..., the way the other dock scenarios make
# one: a third icon joins at the bottom and the remembered order grows with it,
# and it is the class that is closed and launched again below.
open_command dockz foot --app-id=dockz
dock_wait_order "kitty foot dockz" || fail "the third app is not at the bottom: '$(dock_order)'"
assert_eq "$(dock_state_order)" "kitty foot dockz" "the remembered order is the column"

close_class kitty
dock_wait_order "foot dockz" || fail "the closed app's class stayed in the column: '$(dock_order)'"

open_window kitty
dock_wait_order "foot dockz kitty" || fail "a relaunched app must be new and go to the bottom: '$(dock_order)'"
assert_eq "$(dock_state_order)" "foot dockz kitty" "the relaunch moved kitty to the bottom"

dock_stop
