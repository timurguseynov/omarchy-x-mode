#!/usr/bin/env bash
# A click on an icon whose app lives on another workspace moves to that
# workspace and focuses the window, instead of being ignored as "already
# focused". The dock used to skip a class whose window had focusHistoryID 0,
# which is true for a window on a workspace that is not being viewed.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window kitty
dock_settle

nest_ctl dispatch "hl.dsp.window.move({ workspace = \"2\", window = 'class:kitty' })" >/dev/null
kitty_on_2() {
  nest_ctl clients -j | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c.get("class") == "kitty" and not c.get("hidden"):
        raise SystemExit(0 if (c.get("workspace") or {}).get("id") == 2 else 1)
raise SystemExit(1)
'
}
# A tight poll keeps the nest's socket busy, and the dock's own hyprctl then
# never lands, so the click is handled against the list from before the move.
# These sleeps leave the socket free.
for _ in $(seq 1 12); do
  kitty_on_2 && break
  sleep 0.25
done
kitty_on_2 || fail "kitty did not land on workspace 2"
nest_ctl dispatch "hl.dsp.focus({ workspace = \"1\" })" >/dev/null
sleep 0.5
assert_eq "$(viewed_workspace)" 1 "the test starts on workspace 1"
# The column has to be the two-icon card before the click is aimed, or the
# point for the second icon falls in the padding under a one-icon card.
dock_settle

read -r px py <<<"$(dock_icon_point 1)"
pointer_click "$px" "$py"
on_kitty_ws() { [ "$(viewed_workspace)" = 2 ] && [ "$(active_class)" = kitty ]; }
for _ in $(seq 1 12); do
  on_kitty_ws && break
  sleep 0.25
done

assert_eq "$(viewed_workspace)" 2 "clicking the icon switches to the app's workspace (got $(viewed_workspace))"
assert_eq "$(active_class)" kitty "clicking the icon focuses the window there (got $(active_class))"

dock_stop
