#!/usr/bin/env bash
# Compact tabs: one Chrome-like titlebar row. Tabs prefer 240px and shrink so a
# + button and a drag handle still fit; grouping must not grow a second row.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"
printf '%s\n' '{"options":{"compactTabs":true},"apps":{}}' > "$SETTINGS"
nest_ctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null

open_window foot
# Wide enough for two 240px tabs plus the + and a drag handle, but not a snap
# zone: dragging a maximized window would restore and change the size.
place_frac foot 20 18 65 55
read -r _ y0 _ h0 _ <<<"$(win_geom foot)"

open_window foot 2
assert_eq "$(group_size foot)" 2 "the second foot joins the group"

read -r x y w h _ <<<"$(win_geom foot)"
# Without compact, joining grows the chrome by tab_height and absorb_chrome_growth
# moves the box down. One row means the content y stays put.
assert_eq "$y" "$y0" "grouping must not grow a second chrome row"
assert_eq "$h" "$h0" "grouping must not shrink the box for a tabbar"

read -r left tabw plusx plusw bh <<<"$(compact_strip foot 2)"
python3 -c "
left, tabw, plusx, plusw, w = float('$left'), float('$tabw'), float('$plusx'), float('$plusw'), float('$w')
assert tabw <= 240.01, f'tabs must not stretch past 240px, got {tabw}'
assert plusx + plusw + 72 <= w + 1, f'no drag handle after the +: plusx={plusx} plusw={plusw} w={w}'
assert tabw * 2 + left + plusw < w, f'tabs filled the bar: left={left} tabw={tabw} w={w}'
"

# Leftover after the + is a window drag, not a tab.
read -r dx dy <<<"$(compact_drag_point foot 2)"
pointer_drag "$dx" "$dy" "$((dx - 60))" "$((dy + 60))"
wait_still foot
read -r x1 y1 w1 h1 _ <<<"$(win_geom foot)"
assert_eq "$w1" "$w" "a drag-handle drag must not resize"
assert_eq "$h1" "$h" "a drag-handle drag must not resize"
assert_le "$x1" $((x - 30)) "the window follows the leftover handle to the left"
assert_ge "$y1" $((y + 30)) "the window follows the leftover handle down"

# A tab click is still a click.
read -r tx ty <<<"$(compact_tab_point foot 0 2)"
pointer_click "$tx" "$ty"
read -r x2 y2 _ _ _ <<<"$(win_geom foot)"
assert_eq "$x2" "$x1" "clicking a compact tab must not move the window"
assert_eq "$y2" "$y1" "clicking a compact tab must not move the window"
