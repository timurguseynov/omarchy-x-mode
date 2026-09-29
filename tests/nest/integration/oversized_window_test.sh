#!/usr/bin/env bash
# A window that has already settled, then grown to twice the monitor. Hyprland
# resizes a float around its centre and does not refit it, so the top walks up
# under the bar. The bar refits on that same resize: the chrome stays below the
# bar and the box comes back inside the monitor.
. "$(dirname "$0")/../../lib.sh"

open_window foot
# Past the old open-time watch, so this is the settled window, not the one that
# just mapped.
wait_still foot

extent="$(pointer_extent)"
mw="${extent%x*}"
mh="${extent#*x}"
req_w=$((mw * 2))
req_h=$((mh * 2))
assert_ge "$req_w" $((mw + 1)) "the requested width is larger than the monitor"
assert_ge "$req_h" $((mh + 1)) "the requested height is larger than the monitor"

nest_ctl dispatch "hl.dsp.window.resize({ x = $req_w, y = $req_h, relative = false, window = 'class:foot' })" >/dev/null
settle

read -r x y w h _ <<<"$(win_geom foot)"
[ -n "$w" ] || fail "foot has no geometry after the resize"

bar="$(bar_top)"
assert_ge "$(visual_top foot)" "$bar" "a window grown past the monitor stays below the bar"
assert_ge "$x" 0 "the grown window does not hang off the left"
assert_ge "$y" "$bar" "the box stays below the bar"
assert_le "$w" "$mw" "the grown window is no wider than the monitor"
assert_le "$h" "$mh" "the grown window is no taller than the monitor"
assert_le $((x + w)) "$mw" "the grown window stays on the monitor"
assert_le $((y + h)) "$mh" "the grown window stays on the monitor"
