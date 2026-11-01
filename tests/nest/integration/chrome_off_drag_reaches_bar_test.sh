#!/usr/bin/env bash
# Without chrome the clamp must not reserve a titlebar. Dragging such a window to
# the top lets its box reach the bar (one inset below it), where a window with a
# titlebar stops a further 28px down.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

extent="$(pointer_extent)"
mw="${extent%x*}"

printf '%s\n' '{"options":{},"apps":{"foot":{"chrome":false}}}' > "$SETTINGS"
refresh_apps

open_window foot
# Not a drag: a window with no chrome has no titlebar to grab, so the drag helper
# would start outside every window and nothing would move. What this checks is the
# clamp, so the window is put at the top of the screen and the clamp is left to
# decide where it lands.
nest_ctl dispatch "hl.dsp.window.move({ x = $((mw / 2)), y = 0, relative = false, window = 'class:foot' })" >/dev/null
settle

read -r _ y _ _ _ <<<"$(win_geom foot)"
assert_ge "$y" 24 "the window stays below the bar"
assert_le "$y" 40 "without chrome the box reaches the bar, not the titlebar inset"
