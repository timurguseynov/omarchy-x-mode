#!/usr/bin/env bash
# Cmd+W is one of the occupied keys, like Cmd+Q and Cmd+F: a class that steals it
# gets Ctrl+W instead of the pack closing the window, and a class that does not
# still closes. The key had a replacement flag of its own before (ctrlW), so a
# file the older panel wrote -- a plain "ctrlW": true -- has to keep working as
# the W steal it always meant.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

open_window kitty

# What the older panel wrote: the flag, folded onto the W steal on the way in.
printf '%s\n' '{"options":{},"apps":{"kitty":{"ctrlW":true}}}' > "$SETTINGS"
refresh_apps
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
key super+w
settle
assert_eq "$(count_class kitty)" 1 "the old ctrlW flag keeps handing Super+W to the app"

# What this panel writes: the key in the steal list, next to Q and F.
printf '%s\n' '{"options":{},"apps":{"kitty":{"ctrlAsSuperKeys":["W"]}}}' > "$SETTINGS"
refresh_apps
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
key super+w
settle
assert_eq "$(count_class kitty)" 1 "a stolen W hands Super+W to the app"

open_window foot
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
key super+w
settle

assert_eq "$(count_class foot)" 0 "a class that does not steal W still closes"
assert_eq "$(count_class kitty)" 1 "the stolen window is untouched"
