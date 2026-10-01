#!/usr/bin/env bash
# A class with the per-app "Super+W sends Ctrl+W" flag keeps its window: the pack
# hands the key to the app instead of closing. A class without the flag still
# closes, so the flag is what decides, not the key.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

open_window kitty
printf '%s\n' '{"options":{},"apps":{"kitty":{"ctrlW":true}}}' > "$SETTINGS"
refresh_apps

nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
key super+w
settle

assert_eq "$(count_class kitty)" 1 "a flagged class hands Super+W to the app"

open_window foot
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
key super+w
settle

assert_eq "$(count_class foot)" 0 "an unflagged class still closes"
assert_eq "$(count_class kitty)" 1 "the flagged window is untouched"
