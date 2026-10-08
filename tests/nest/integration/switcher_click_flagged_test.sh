#!/usr/bin/env bash
# A click on an icon in the app switcher switches to that app, even when the
# window under the pointer is the one whose card turns Cmd+click into Ctrl+click.
#
# The row only exists while Cmd is held, so a click on it is always a Cmd+click
# -- which is exactly the bind the pack installs for the Ctrl+click flag. That
# bind looked at the window under the cursor, found the flagged one behind the
# row and took the click as a Ctrl+click *in it*: the row never saw the click,
# the app did not change, and the window below the row was clicked instead.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"
extent="$(pointer_extent)"
mw="${extent%x*}"
mh="${extent#*x}"

# The window the row will be over says Cmd+click is Ctrl+click.
printf '%s\n' '{"options":{},"apps":{"footzed":{"ctrlClick":true}}}' > "$SETTINGS"
refresh_apps

open_command footzed foot -a footzed
open_window kitty
open_window foot

dock_start
dock_settle

# Which window is under the pointer has to be the flagged one, so it covers the
# row's first icon (whole work area) and the two apps of the row stay clear of
# it, on the right.
place() { # CLASS X Y W H
  nest_ctl dispatch "hl.dsp.window.move({ x = $2, y = $3, relative = false, window = 'class:$1' })" >/dev/null
  nest_ctl dispatch "hl.dsp.window.resize({ x = $4, y = $5, relative = false, window = 'class:$1' })" >/dev/null
  sleep 0.25
}
snap footzed maximize
place kitty $(( mw - mw / 3 )) 80 $(( mw / 3 - 40 )) 200
place foot $(( mw - mw / 3 )) 320 $(( mw / 3 - 40 )) 200

# The first icon is a screen centre minus one icon and one spacing; the click
# goes there, so whether the premise holds has to be said out loud.
click_x=$(( mw / 2 - 62 ))
click_y=$(( mh / 2 ))
covers() { # CLASS X Y -> yes|no
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] != '$1' or not c['mapped'] or c.get('hidden'):
        continue
    x, y = c['at']; w, h = c['size']
    print('yes' if x <= $2 < x + w and y <= $3 < y + h else 'no')
    break
else:
    print('no')"
}
assert_eq "$(covers footzed "$click_x" "$click_y")" yes "the flagged window is under the icon"
assert_eq "$(covers kitty "$click_x" "$click_y")" no "the app the click is aimed at is not"
assert_eq "$(covers foot "$click_x" "$click_y")" no "and neither is the one it previews"

# The row is the MRU order, so the last focus is its first icon: kitty, then
# foot, then the flagged window behind them.
for cls in footzed foot kitty; do
  nest_ctl dispatch "hl.dsp.focus({ window = 'class:$cls' })" >/dev/null
  sleep 0.3
done
assert_eq "$(active_class)" kitty "kitty is the app the row starts on"

# Hold Cmd and Tab: the row comes up and previews the app after kitty, and it
# stays up while Cmd is held (the hold is what a person does with the keys).
key -h 2500 super+tab &
holding=$!
wait_until 3 '[ "$(active_class)" = foot ]'
assert_eq "$(active_class)" foot "the held Cmd+Tab previewed the app after kitty (got $(active_class))"

# A click on that icon is a click on kitty, not a Ctrl+click in the flagged
# window it is drawn over.
pointer_click "$click_x" "$click_y"
wait_until 3 '[ "$(active_class)" = kitty ]'
assert_eq "$(active_class)" kitty "a click on an icon switches to that app (got $(active_class))"

wait "$holding" 2>/dev/null || true
