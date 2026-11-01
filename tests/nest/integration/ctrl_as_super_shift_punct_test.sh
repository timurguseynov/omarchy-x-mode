#!/usr/bin/env bash
# A punctuation key takes a Shift variant too. Hyprland resolves a bind's key
# through a keyboard state with no modifiers (`m_xkbTranslationState`,
# KeybindManager::onKeyEvent), so `SUPER + SHIFT + backslash` fires on
# Shift+backslash even though that press produces `bar`. That is what the map
# needs for Cmd+Shift+\ to reach the app as Ctrl+Shift+\, the chord Zed reads as
# `ctrl-|` for "reveal in the file tree".
#
# The app is a kitty with its keyboard protocol on (`CSI >1u`), so the bytes say
# which modifiers arrived: `CSI 92;6u` is `\` with Ctrl+Shift (1 + Shift 1 + Ctrl
# 4), and a key Hyprland had left to the app would be `CSI 92;10u` (Super+Shift).
# Kitty's legacy encoding drops the control for a shifted symbol and sends the
# same `|` either way, which reads as a pass-through that is not there.
. "$(dirname "$0")/../../lib.sh"

CAP="$NEST_STATE/ctrl-as-super-shift-punct.out"
SETTINGS="$NEST_SETTINGS"

# Modmask 65 is Super+Shift. The whole description is matched: `backslash` alone
# would also match the plain `x-mode-super-ctrl backslash`.
generated_shift_for() { # KEY
  nest_ctl binds -j | python3 -c "
import json, sys
want = ('x-mode-super-ctrl shift ' + '$1').lower()
print(sum(1 for b in json.load(sys.stdin)
          if (b.get('description') or '').lower() == want and int(b.get('modmask') or 0) == 65))"
}

printf '%s\n' '{"options":{},"apps":{"kitty":{"ctrlAsSuper":true}}}' > "$SETTINGS"
refresh_apps
# The map is written out of band (an exec writes the table, a timer picks it up),
# so the condition stays text: a substituted one is checked once, and a bind that
# lands a moment later reads as never generated.
wait_until 5 '[ "$(generated_shift_for backslash)" = 1 ]' || fail "no Ctrl+Shift+\\ bind was generated for a free punctuation key"
assert_eq "$(generated_shift_for slash)" 1 "the other punctuation keys take their Shift variant as well"
assert_eq "$(generated_shift_for TAB)" 0 "a named key keeps its Shift chord to the pack"

rm -f "$CAP"
open_command kitty kitty sh -c "printf '\\033[>1u'; stty raw -echo; cat > '$CAP'"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.4
key super+shift+backslash
sleep 0.5

got=$(od -An -v -tx1 "$CAP" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//')
printf '  note: the app received %s\n' "'$got'"
assert_eq "$got" "1b 5b 39 32 3b 36 75" "Cmd+Shift+\\ reaches the app as Ctrl+Shift+\\"
