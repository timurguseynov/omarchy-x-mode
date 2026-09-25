#!/usr/bin/env bash
# A pinned window is above fullscreen by design: CWindow::isAllowedOverFullscreen
# returns true for m_pinned, updateFullscreenInputState leaves its input alone,
# and Hyprland's own fullscreen fade skips pinned windows. The pack's hold used
# to clear the raw flag and force the fade to 0 anyway, so a focused pinned
# window stopped being raised and went invisible while still taking input.
#
# allowedOverFullscreen in hyprctl is the raw flag the hold clears, and for a
# pinned window it has to stay true (isAllowedOverFullscreen then keeps it
# visible and override-free).
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

open_window kitty
nest_ctl dispatch "hl.dsp.window.pin({ action = 'enable', window = 'class:kitty' })" >/dev/null
sleep 0.3
assert_eq "$(client_field kitty pinned)" true "kitty is pinned"

open_window foot
nest_ctl dispatch "hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set', window = 'class:foot' })" >/dev/null
sleep 0.3

# Focusing the floating window is what marks it allowed over fullscreen, and
# what the pack's hold reacts to.
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3

assert_eq "$(client_field kitty allowedOverFullscreen)" true "a pinned window stays allowed over fullscreen"
assert_eq "$(client_field kitty acceptsInput)" true "a pinned window keeps taking input"
assert_eq "$(active_class)" kitty "a pinned window keeps the focus"
