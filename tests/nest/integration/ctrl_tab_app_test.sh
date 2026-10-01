#!/usr/bin/env bash
# "Super+Tab switches tabs" hands Super+Tab to the app as Ctrl+Tab instead of
# opening the desktop's app switcher. What a test can see of the switcher is its
# command file, so that is what this reads: written when the pack ran it, absent
# when the key went to the app.
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

printf '%s\n' '{"options":{},"apps":{"kitty":{"ctrlTab":true}}}' > "$SETTINGS"
refresh_apps

rm -f "$NEST_RUNTIME/omarchy-switcher.cmd"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
key super+tab
settle
assert_eq "$(active_class)" kitty "a flagged app keeps the focus, no switcher"
assert_eq "$(switcher_bytes)" 0 "the switcher did not run"

rm -f "$NEST_RUNTIME/omarchy-switcher.cmd"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
before="$(active_class)"
key super+tab
settle
assert_ne "$(active_class)" "$before" "an unflagged app still gets the switcher"
assert_ge "$(switcher_bytes)" 1 "the switcher's command file was written"
