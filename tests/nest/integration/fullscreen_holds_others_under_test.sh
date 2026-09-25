#!/usr/bin/env bash
# One fullscreen window owns the workspace. Focusing another floating window
# must not lift it: Hyprland marks a focused floater allowed over fullscreen,
# and the pack's raise would stack it on top. After fullscreen is gone, focus
# raises normally again.
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
open_window kitty

nest_ctl dispatch "hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set', window = 'class:foot' })" >/dev/null
sleep 0.3
assert_eq "$(client_field foot fullscreen)" 2 "foot is fullscreen"

# The punch: a focus dispatch on a floating window marks it allowed over the
# fullscreen one. The pack has to put that back.
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
assert_eq "$(client_field kitty allowedOverFullscreen)" false "kitty stays under the fullscreen window"
assert_eq "$(client_field kitty acceptsInput)" false "kitty takes no input while foot is fullscreen"
assert_eq "$(client_field foot fullscreen)" 2 "foot is still fullscreen"
assert_eq "$(active_class)" foot "keyboard focus stays on the fullscreen window"

nest_ctl dispatch "hl.dsp.window.fullscreen({ action = 'unset', window = 'class:foot' })" >/dev/null
sleep 0.3
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
assert_eq "$(topmost)" kitty "without fullscreen, focus raises the window again"
assert_eq "$(active_class)" kitty "kitty keeps focus once nothing is fullscreen"
