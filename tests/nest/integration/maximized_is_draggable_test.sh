#!/usr/bin/env bash
# A client maximize (Zed requests this on startup) used to enter Hyprland's
# maximized mode. That mode ignores later moves, so the titlebar drag does
# nothing. The pack turns it into the floating maximize, which can be moved.
. "$(dirname "$0")/../../lib.sh"

client_field() { # CLASS FIELD
  nest_ctl clients -j | CLASS="$1" FIELD="$2" python3 -c '
import json, os, sys
cls, field = os.environ["CLASS"], os.environ["FIELD"]
for c in json.load(sys.stdin):
    if c.get("class") == cls and c.get("mapped"):
        v = c.get(field)
        print("true" if v is True else "false" if v is False else "" if v is None else v)
        break
else:
    print("")
'
}

open_window foot

nest_ctl dispatch "hl.dsp.window.fullscreen({ mode = 'maximized', action = 'set', window = 'class:foot' })" >/dev/null
sleep 0.5

assert_eq "$(client_field foot fullscreen)" 0 "a maximize request does not stay in Hyprland's maximized mode"
assert_ge "$(visual_top foot)" "$(bar_top)" "the floating maximize stays below the bar"

# Shrink to a small box first: the floating maximize fills the work area, so a
# 200x160 box in the corner is what shows the move, not one already against every
# edge.
nest_ctl dispatch "hl.dsp.window.resize({ x = 200, y = 160, relative = false, window = 'class:foot' })" >/dev/null
nest_ctl dispatch "hl.dsp.window.move({ x = 80, y = 100, relative = false, window = 'class:foot' })" >/dev/null
sleep 0.3
read -r x y w h _ <<<"$(win_geom foot)"
assert_eq "$w" 200 "the window accepts a resize after a maximize request"
assert_eq "$h" 160 "the window accepts a resize after a maximize request"
assert_eq "$x" 80 "the window moves after a maximize request"
assert_eq "$y" 100 "the window moves after a maximize request"
