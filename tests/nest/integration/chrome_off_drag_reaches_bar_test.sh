#!/usr/bin/env bash
# Without chrome the clamp must not reserve a titlebar. Dragging such a window to
# the top lets its box reach the bar (one inset below it), where a window with a
# titlebar stops a further 28px down.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

extent="$(pointer_extent)"
mw="${extent%x*}"

printf '%s\n' '{"options":{},"apps":{"foot":{"chrome":false}}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

open_window foot
drag_to foot $((mw / 2)) 2

read -r _ y _ _ _ <<<"$(win_geom foot)"
assert_ge "$y" 24 "the window stays below the bar"
assert_le "$y" 40 "without chrome the box reaches the bar, not the titlebar inset"
