#!/usr/bin/env bash
# Holding a Cmd+key that the pack hands to the app as Ctrl+key is a *repeated*
# Ctrl+key, the way it is on a Mac: Sublime's hold-Cmd+D adds one occurrence
# after another. The two halves of that are separate:
#
#   * the chord has to be whole by itself (Ctrl down, key down, key up, Ctrl up)
#     and not share its release with the physical key. Handing the app a key it
#     then holds -- with the Ctrl already released -- makes the app's own repeat
#     type the bare letter: Cmd+D selected once and then wrote "d".
#   * the bind repeats while the key is held, so what arrives per repeat is
#     another whole chord rather than one chord and then a stuck key.
#
# The app is foot in raw mode, so every byte the terminal would send for a key
# is in the file: Ctrl+D is 0x04 and a bare "d" is 0x64. D is free in the nest
# (Omarchy binds Cmd+Shift+D, not Cmd+D), so the generated map takes it.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"
CAP="$NEST_STATE/super-ctrl-hold.out"

# A generated bind for one key: the map writes "x-mode-super-ctrl <KEY>".
mapped() { # KEY
  nest_ctl binds -j | python3 -c "
import json, sys
want = ('x-mode-super-ctrl ' + '$1').lower()
print(sum(1 for b in json.load(sys.stdin)
          if (b.get('description') or '').lower() == want and int(b.get('modmask') or 0) == 64))"
}

# How many times a byte appears in what the app received.
byte_count() { # HEX
  od -An -v -tx1 "$CAP" 2>/dev/null | tr -s ' \n' '\n' | grep -cx "$1" || true
}

CTRL_D=04
BARE_D=64

printf '%s\n' '{"options":{},"apps":{"holdzed":{"ctrlAsSuper":true}}}' > "$SETTINGS"
refresh_apps
wait_until 5 '[ "$(mapped D)" = 1 ]' || fail "Super as Ctrl never mapped D"

rm -f "$CAP"
open_command holdzed foot -a holdzed sh -c "stty raw -echo; cat > '$CAP'"
wait_until 3 '[ -e "$CAP" ]' || fail "the capture window did not open"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:holdzed' })" >/dev/null
sleep 0.3

# One press is one Ctrl+D, and nothing else: the app is not left holding a key
# it never released.
key super+d
sleep 0.5
assert_eq "$(byte_count $CTRL_D)" 1 "one press hands over one Ctrl+D (saw $(byte_count $CTRL_D))"
assert_eq "$(byte_count $BARE_D)" 0 "a press on its own types nothing (saw $(byte_count $BARE_D) bare d)"

# Holding it: every repeat is another whole chord, and the app's own repeat
# never gets a bare key to type.
before="$(byte_count $CTRL_D)"
key -h 2000 super+d
sleep 0.6
assert_eq "$(byte_count $BARE_D)" 0 "a held Cmd+D never types the bare letter (saw $(byte_count $BARE_D) of them)"
repeats="$(( $(byte_count $CTRL_D) - before ))"
[ "$repeats" -ge 3 ] || fail "a held Cmd+D should repeat Ctrl+D (saw $repeats of them)"
