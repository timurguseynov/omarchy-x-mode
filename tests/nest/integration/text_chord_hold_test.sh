#!/usr/bin/env bash
# A held text chord repeats. On a Mac, Option+Backspace deletes a word and keeps
# deleting while it is held, Cmd+Left jumps to the start of each line as it
# repeats, and so on -- the OS repeats the key and the app answers every repeat.
# Here the chord is the pack's (the app is handed Ctrl+W in a terminal, or
# Ctrl+Backspace in a toolkit), so the repeat has to be the bind's: the chord is
# sent whole (down and up) and the app is left holding nothing to repeat.
#
# The window is tagged "terminal", which is the context the text chords answer
# for, so Option+Backspace is Ctrl+W -- 0x17 in a raw terminal, a byte no other
# part of the chord can produce.
. "$(dirname "$0")/../../lib.sh"

CAP="$NEST_STATE/text-chord-hold.out"
CTRL_W=17

byte_count() { # HEX
  od -An -v -tx1 "$CAP" 2>/dev/null | tr -s ' \n' '\n' | grep -cx "$1" || true
}

nest_ctl eval 'hl.window_rule({ match = { class = "holdzed" }, tag = "+terminal" })' >/dev/null

rm -f "$CAP"
open_command holdzed foot -a holdzed sh -c "stty raw -echo; cat > '$CAP'"
wait_until 3 '[ -e "$CAP" ]' || fail "the capture window did not open"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:holdzed' })" >/dev/null
sleep 0.3

# One press is one word: Ctrl+W, and nothing else.
key alt+backspace
sleep 0.5
assert_eq "$(byte_count $CTRL_W)" 1 "one press deletes one word"

# Holding it: the repeat deletes word after word.
before="$(byte_count $CTRL_W)"
key -h 2000 alt+backspace
sleep 0.6
repeats="$(( $(byte_count $CTRL_W) - before ))"
[ "$repeats" -ge 3 ] || fail "a held Option+Backspace should keep deleting words (saw $repeats: one for the press and none after it)"
