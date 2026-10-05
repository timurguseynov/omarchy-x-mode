#!/usr/bin/env bash
# What the panel is offered to steal. A key the pack binds itself is not on that
# list even when Omarchy's source has a command for it: on Cmd+Backspace she had
# window transparency and the pack has a text chord ("Delete to start of line"),
# so a steal would wrap the chord away and replay *her* transparency for every app
# that did not steal it. Her own key is still on the list, action and all: hyprctl
# prints only `__lua` for a bind she made with a function, and the command is read
# out of her bind files.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"
OCC="$NEST_STATE/state/occupied.json"

listed() { # ID -> yes / no
  python3 -c "
import json, sys
try:
    data = json.load(open('$OCC'))
except Exception:
    sys.exit(1)
print('yes' if any(str(e.get('id')) == '$1' for e in data) else 'no')"
}

# Her K, the way her file writes it: the action behind it is a command, but bound
# through a Lua function the bind table only says __lua.
nest_ctl eval 'hl.bind("SUPER + K", function() end, { description = "Keybindings" })' >/dev/null

printf '%s\n' '{"options":{},"apps":{}}' > "$SETTINGS"
refresh_apps
# K is the one that guarantees the list was written after the bind above: the pack's
# own keys are in it from the config load, so waiting for one of those would read a
# list written before the bind landed.
wait_until 5 '[ "$(listed K)" = yes ]' || fail "the occupied list never listed K"

assert_eq "$(listed W)" yes "the pack's own close key is offered"
assert_eq "$(listed K)" yes "Omarchy's own bind is, through the command read out of her file"
assert_eq "$(listed BACKSPACE)" no "a key the pack binds itself is not: transparency is not what it does here"
assert_eq "$(listed DELETE)" no "nor are the other text chords"
