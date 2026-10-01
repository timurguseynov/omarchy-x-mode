#!/usr/bin/env bash
# Super+Tab is the desktop's app switcher for every app. "Super works as Ctrl"
# only fills in the keys the desktop does not use, so it must not take Cmd+Tab
# with it: a flagged app gets the switcher too. What a test can see of the
# switcher is its command file.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

switcher_bytes() {
  if [ -f "$NEST_RUNTIME/omarchy-switcher.cmd" ]; then
    wc -c < "$NEST_RUNTIME/omarchy-switcher.cmd"
  else
    echo 0
  fi
}

open_window kitty
open_window foot

printf '%s\n' '{"options":{},"apps":{"kitty":{"ctrlAsSuper":true}}}' > "$SETTINGS"
refresh_apps

rm -f "$NEST_RUNTIME/omarchy-switcher.cmd"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
before="$(active_class)"
key super+tab
settle
assert_ne "$(active_class)" "$before" "Super+Tab still switches apps for a flagged app"
assert_ge "$(switcher_bytes)" 1 "the switcher is what ran"

rm -f "$NEST_RUNTIME/omarchy-switcher.cmd"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
before="$(active_class)"
key super+tab
settle
assert_ne "$(active_class)" "$before" "and for an unflagged one"
assert_ge "$(switcher_bytes)" 1 "the switcher is what ran"
