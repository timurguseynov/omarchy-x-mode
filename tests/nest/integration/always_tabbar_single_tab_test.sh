#!/usr/bin/env bash
# alwaysTabbar draws the tabbar for a lone window too. The chrome above the box
# grows by the tabbar height, so the box is pushed a tabbar lower than a plain
# window, and snapping it still must not create a group.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

printf '%s\n' '{"options":{},"apps":{"foot":{"chrome":true,"alwaysTabbar":true}}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

open_window foot
snap foot left

read -r _ y _ _ _ <<<"$(win_geom foot)"
# 24 (bar) + 12 (gaps+border) + 28 (titlebar) + 24 (tabbar)
assert_ge "$y" 88 "the tabbar pushes the box down"
assert_le "$(group_size foot)" 1 "a lone window is not grouped by snapping"
