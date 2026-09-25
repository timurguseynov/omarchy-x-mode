#!/usr/bin/env bash
# A window that has already settled, then grown to twice the monitor. The
# open-time watch has stopped by then, and Hyprland does not refit a floating
# window when it is resized, so nothing is required to pull this box back.
# The lines below are the result: where it landed, and how far it hangs off
# each edge of the monitor.
. "$(dirname "$0")/../../lib.sh"

open_window foot
# watch_until_settled runs for at most 2s from map. open_window already waited
# for the window, so this clears the rest of that watch before the resize.
sleep 2.2

extent="$(pointer_extent)"
mw="${extent%x*}"
mh="${extent#*x}"
req_w=$((mw * 2))
req_h=$((mh * 2))
assert_ge "$req_w" $((mw + 1)) "the requested width is larger than the monitor"
assert_ge "$req_h" $((mh + 1)) "the requested height is larger than the monitor"

nest_ctl dispatch "hl.dsp.window.resize({ x = $req_w, y = $req_h, relative = false, window = 'class:foot' })" >/dev/null
sleep 0.6

read -r x y w h _ <<<"$(win_geom foot)"
[ -n "$w" ] || fail "foot has no geometry after the resize"

bar="$(bar_top)"
python3 - "$mw" "$mh" "$bar" "$req_w" "$req_h" "$x" "$y" "$w" "$h" <<'PY'
import sys
mw, mh, bar, req_w, req_h, x, y, w, h = (int(v) for v in sys.argv[1:])
print(f"monitor {mw}x{mh}, bar {bar}")
print(f"asked {req_w}x{req_h}")
print(f"landed at {x},{y} size {w}x{h}")
print(
    "hangs off"
    f" left {max(0, -x)}, right {max(0, x + w - mw)},"
    f" top {max(0, bar - (y - 28))}, bottom {max(0, y + h - mh)}"
)
PY
