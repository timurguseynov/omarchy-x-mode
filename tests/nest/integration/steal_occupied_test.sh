#!/usr/bin/env bash
# Occupied Super keys stay with the desktop until an app steals them. The pack
# wraps the bind (like Super+W): the flagged app gets Ctrl+key, everyone else
# keeps the original action. Super+Q, Super+Tab and Super+F are pack wraps.
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

SETTINGS="$NEST_SETTINGS"

open_window kitty
open_window foot

# Super+Q closes the app until kitty steals it.
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
printf '%s\n' '{"options":{},"apps":{"kitty":{"ctrlAsSuperKeys":["Q"]}}}' > "$SETTINGS"
refresh_apps
sleep 0.6
key super+q
settle
assert_eq "$(count_class kitty)" 1 "a stolen Super+Q does not quit the flagged app"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
key super+q
settle
assert_eq "$(count_class foot)" 0 "an unflagged app still quits on Super+Q"
assert_eq "$(count_class kitty)" 1 "the flagged window is untouched"

# Super+Tab is the switcher until kitty steals it.
open_window foot
printf '%s\n' '{"options":{},"apps":{"kitty":{"ctrlAsSuperKeys":["TAB"]}}}' > "$SETTINGS"
refresh_apps
sleep 0.6

rm -f "$NEST_RUNTIME/omarchy-switcher.cmd"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
before="$(active_class)"
key super+tab
settle
assert_eq "$(active_class)" "$before" "a stolen Super+Tab does not switch apps"
if [ -f "$NEST_RUNTIME/omarchy-switcher.cmd" ]; then
  assert_eq "$(cat "$NEST_RUNTIME/omarchy-switcher.cmd")" "hide" "the switcher did not open for a stolen Tab"
fi

rm -f "$NEST_RUNTIME/omarchy-switcher.cmd"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
before="$(active_class)"
key super+tab
settle
assert_ne "$(active_class)" "$before" "an unflagged app still gets the switcher"
assert_ge "$( [ -f "$NEST_RUNTIME/omarchy-switcher.cmd" ] && wc -c < "$NEST_RUNTIME/omarchy-switcher.cmd" || echo 0 )" 1 "the switcher is what ran"

# Super+F is Omarchy fullscreen (a Lua dispatcher). The pack wraps it at the
# source like Super+Q, so a steal is Find and everyone else still goes fullscreen.
nest_ctl dispatch "hl.dsp.window.fullscreen({ action = 'unset', window = 'class:foot' })" >/dev/null
nest_ctl dispatch "hl.dsp.window.fullscreen({ action = 'unset', window = 'class:kitty' })" >/dev/null
settle
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
key super+f
settle
assert_eq "$(client_field foot fullscreen)" 2 "an unflagged Super+F is still fullscreen"

nest_ctl dispatch "hl.dsp.window.fullscreen({ action = 'unset', window = 'class:foot' })" >/dev/null
settle
printf '%s\n' '{"options":{},"apps":{"kitty":{"ctrlAsSuperKeys":["F"]}}}' > "$SETTINGS"
refresh_apps
sleep 0.6

nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
key super+f
settle
assert_eq "$(client_field kitty fullscreen)" 0 "a stolen Super+F does not fullscreen the flagged app"
assert_eq "$(client_field foot fullscreen)" 0 "the other window stays out of fullscreen"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
key super+f
settle
assert_eq "$(client_field foot fullscreen)" 2 "an unflagged app still goes fullscreen on Super+F"

# Ctrl+Cmd+F is the macOS fullscreen key, and it is what is left when the app
# took Cmd+F for Find -- so it does not look at the steal at all. Omarchy's own
# Ctrl+Cmd+F (tiled fullscreen) is dropped by the pack, so the key is ours.
assert_eq "$(bind_count_desc_exact "Full screen" 68)" 1 "Ctrl+Cmd+F is the pack's fullscreen"
assert_eq "$(bind_count_desc "Tiled full screen" 68)" 0 "Omarchy's tiled fullscreen is gone"

nest_ctl dispatch "hl.dsp.window.fullscreen({ action = 'unset', window = 'class:kitty' })" >/dev/null
nest_ctl dispatch "hl.dsp.window.fullscreen({ action = 'unset', window = 'class:foot' })" >/dev/null
settle
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
key super+ctrl+f
settle
assert_eq "$(client_field kitty fullscreen)" 2 "Ctrl+Cmd+F fullscreens the app that stole Cmd+F"

key super+ctrl+f
settle
assert_eq "$(client_field kitty fullscreen)" 0 "and it toggles back like Cmd+F"
