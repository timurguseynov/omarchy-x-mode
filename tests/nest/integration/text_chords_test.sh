#!/usr/bin/env bash
# The macOS text chords: the desktop sends what the focused app understands. A
# terminal (Omarchy tags it "terminal") needs readline's chords -- Ctrl+W for a
# word, Ctrl+U for the line, Alt+D for a word forward -- and every other app
# needs its toolkit's. They are not interchangeable (Ctrl+Backspace is a word
# delete in GTK and a single character to readline), so this drives real keys
# and reads the bytes the app actually received.
#
# One window per step: two windows of one class make `class:X` an ambiguous
# focus, and the key then lands in the older one, whose dump is not the file.
. "$(dirname "$0")/../../lib.sh"

CAP="$NEST_STATE/text-chords.out"

# The nest loads no Omarchy window rules, so nothing is tagged unless the test
# says so. Omarchy's own rule is the one that tags a terminal "terminal";
# planting it here with a name lets the runner switch it off again.
nest_ctl eval "hl.window_rule({ name = 'text-chords-terminal', match = { class = '(kitty|foottag)' }, tag = '+terminal' })" >/dev/null

# Open CLASS with everything it receives dumped raw, so the chord the pack sent
# is read back as the app saw it. `stty raw -echo` keeps the pty from turning
# Ctrl+U into a line edit and from echoing it back.
capture() { # CLASS COMMAND...
  local cls="$1"
  shift
  rm -f "$CAP"
  open_command "$cls" "$@"
  nest_ctl dispatch "hl.dsp.focus({ window = 'class:$cls' })" >/dev/null
  sleep 0.4
}

received() { od -An -v -tx1 "$CAP" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//'; }

tail_capture() { # LABEL
  sleep 0.5
  printf '  note: %s received %s\n' "$1" "'$(received)'"
}

# Tagged: readline's chords.
capture kitty kitty sh -c "stty raw -echo; cat > '$CAP'"
key alt+delete
tail_capture "tagged Option+Delete"
assert_eq "$(received)" "1b 64" "in a terminal Option+Delete is readline's Alt+D"

capture foottag foot -a foottag sh -c "stty raw -echo; cat > '$CAP'"
key super+backspace
tail_capture "tagged Cmd+Backspace"
assert_eq "$(received)" "15" "in a terminal Cmd+Backspace kills the line with Ctrl+U"

# Untagged: the toolkit's chords, for the same keys.
capture foot foot sh -c "stty raw -echo; cat > '$CAP'"
key alt+delete
tail_capture "untagged Option+Delete"
assert_eq "$(received)" "1b 5b 33 3b 35 7e" "outside a terminal Option+Delete is Ctrl+Delete"

# Cmd+Backspace outside a terminal is a selection then a delete, not Ctrl+U.
# The bytes are the terminal's encoding of Shift+Home (CSI 1;2 H) followed by
# one Backspace: the pair has to land once each, in order.
capture footgui foot -a footgui sh -c "stty raw -echo; cat > '$CAP'"
key super+backspace
tail_capture "untagged Cmd+Backspace"
assert_eq "$(received)" "1b 5b 31 3b 32 48 7f" "outside a terminal Cmd+Backspace selects to the start and deletes once"
