#!/usr/bin/env bash
# Super+Tab (and Super+Shift+Tab, the same step) focuses the next app on the
# key itself, so a fullscreen window has to leave fullscreen then: otherwise
# the focus is pulled back under it. Tabbing while there is only one app does
# not select anything else, and fullscreen stays.
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
nest_ctl dispatch "hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set', window = 'class:foot' })" >/dev/null
sleep 0.3

key super+tab
sleep 0.4
assert_eq "$(client_field foot fullscreen)" 2 "one app: Super+Tab leaves it fullscreen"
assert_eq "$(active_class)" foot "one app: focus stays on foot"

open_window kitty
sleep 0.3
assert_eq "$(client_field foot fullscreen)" 2 "opening another app does not drop fullscreen"
assert_eq "$(active_class)" foot "the fullscreen window keeps focus"

key super+tab
sleep 0.4
assert_eq "$(client_field foot fullscreen)" 0 "Super+Tab leaves fullscreen for the other app"
assert_eq "$(active_class)" kitty "the other app is the one focused"
assert_eq "$(client_field kitty acceptsInput)" true "the other app takes input"
