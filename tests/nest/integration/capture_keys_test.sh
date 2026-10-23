#!/usr/bin/env bash
# The macOS capture keys. Cmd+Shift+3/4 and Ctrl+Shift+Cmd+3/4 are screenshots,
# Cmd+Shift+5 the recording key, Cmd+Shift+6 the OCR region read; each runs the
# Omarchy capture command with the mode the Mac key means.
#
# What this scenario pins is the pack's half of that: which chord, which label,
# on which modifier mask, and that the digit no longer moves the window as well.
# The shot itself is not asserted here any more.
#
# Up to Omarchy 4.0 the plain keys ran grim behind a freeze picker, and a file in
# ~/Pictures was the proof that the whole chain worked. 4.5 replaced that with
# Omasnap (omarchy-capture-screenshot now execs it): an overlay application that
# captures through ext-image-copy-capture and saves into ~/Pictures/Screenshots.
# Started in a nested compositor it exits 0 and writes nothing at all -- no PNG
# under the nest's home, no Omasnap state directory, nothing on stderr -- so the
# file it should produce cannot be asserted from here. The capture itself is a
# check on a real session: Cmd+Shift+3 there writes a file into
# ~/Pictures/Screenshots, and Cmd+Ctrl+Shift+3 puts it on the clipboard.
#
# Cmd+Shift+3..6 are also Omarchy's window moves, written by keycode, and a bind
# matches on its own spelling: left behind, the keycode form would move the
# window as well as take the screenshot. The nest plants them.
. "$(dirname "$0")/../../lib.sh"

# Super is 64, Control 4, Shift 1: Shift+Cmd is 65, Ctrl+Shift+Cmd is 69.
has_bind() { # KEY MODMASK DESCRIPTION
  nest_ctl binds -j | python3 -c "
import json, sys
n = 0
for b in json.load(sys.stdin):
    if b.get('key') == '$1' and int(b.get('modmask') or 0) == int('$2') and (b.get('description') or '') == '$3':
        n += 1
print(n)"
}

assert_eq "$(has_bind 3 65 "Screenshot the screen")" 1 "Cmd+Shift+3 is a full-screen shot"
assert_eq "$(has_bind 3 69 "Screenshot the screen to clipboard")" 1 "Ctrl+Shift+Cmd+3 copies it"
assert_eq "$(has_bind 4 65 "Screenshot a region")" 1 "Cmd+Shift+4 is a region"
assert_eq "$(has_bind 4 69 "Screenshot a region to clipboard")" 1 "Ctrl+Shift+Cmd+4 copies it"
assert_eq "$(has_bind 5 65 "Screen recording")" 1 "Cmd+Shift+5 is the recording key"
assert_eq "$(has_bind 6 65 "Capture text from a region")" 1 "Cmd+Shift+6 reads the text of a region"

for digit in 3 4 5 6; do
  assert_eq "$(bind_count_desc_exact "Move window to workspace $digit" 65)" 0 "Cmd+Shift+$digit no longer moves the window"
done

# The key still runs its command and the compositor survives it: a bind that
# dispatches into something that no longer exists, or a command line that no
# longer parses, showed up as a nest that stopped answering, or as a window that
# went somewhere else.
open_window foot
settle
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
settle
before="$(active_address)"
key super+shift+3
sleep 1
assert_eq "$(active_address)" "$before" "the capture key leaves the focus where it was"
[ -n "$(nest_ctl version 2>/dev/null)" ] || fail "the nest stopped answering after the capture key"

# A capture overlay or picker left open would hold a layer surface for the next
# scenario. Omasnap dismisses the one it finds instead of shooting it, which is
# also why a second run of this scenario cannot be a screenshot test.
pkill -x omasnap 2>/dev/null || true
pkill -x slurp 2>/dev/null || true
