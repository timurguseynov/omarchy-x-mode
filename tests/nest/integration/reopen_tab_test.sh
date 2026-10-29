#!/usr/bin/env bash
# Cmd+Shift+T reopens the last closed tab on a Mac (the app's Ctrl+Shift+T).
# Omarchy keeps Activity (btop) on that key, so it is not a free Super-as-Ctrl
# chord: Shortcuts has its own row, and until that row is on the pack binds
# nothing. On, the focused app is handed Ctrl+Shift+T. Kitty's keyboard protocol
# spells that as CSI 116;6u (T, Shift+Ctrl).
. "$(dirname "$0")/../../lib.sh"

CAP="$NEST_STATE/reopen-tab.out"
SETTINGS="$NEST_SETTINGS"

ours() { bind_count_desc "Reopen closed tab" 65; }

# Any generated Shift chord: the map has been applied.
generated_shift_any() {
  nest_ctl binds -j | python3 -c "
import json, sys
print(sum(1 for b in json.load(sys.stdin)
          if (b.get('description') or '').lower().startswith('x-mode-super-ctrl shift ')
          and int(b.get('modmask') or 0) == 65))"
}

# Super as Ctrl's own Shift+T, if it generated one beside the Shortcuts row.
generated_shift_t() {
  nest_ctl binds -j | python3 -c "
import json, sys
want = 'x-mode-super-ctrl shift t'
print(sum(1 for b in json.load(sys.stdin)
          if (b.get('description') or '').lower() == want and int(b.get('modmask') or 0) == 65))"
}

printf '%s\n' '{"options":{},"apps":{}}' > "$SETTINGS"
refresh_apps
sleep 0.4
assert_eq "$(ours)" 0 "off: Cmd+Shift+T is not taken"

printf '%s\n' '{"options":{},"apps":{"kitty":{"reopenTab":true,"ctrlAsSuper":true}}}' > "$SETTINGS"
refresh_apps
wait_until 5 '[ "$(ours)" = 1 ]' || fail "the Shortcuts row did not bind Cmd+Shift+T"
# Super as Ctrl must not keep a second bind on the same key: Hyprland would run
# both, and the app would see the chord twice. Wait until that map has landed,
# then check T is not in it — a count of zero before the map exists proves nothing.
wait_until 5 '[ "$(generated_shift_any)" -gt 0 ]' || fail "Super as Ctrl generated no binds"
assert_eq "$(generated_shift_t)" 0 "Super as Ctrl left Cmd+Shift+T to the Shortcuts row"

rm -f "$CAP"
open_command kitty kitty sh -c "printf '\\033[>1u'; stty raw -echo; cat > '$CAP'"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.4
key super+shift+t
sleep 0.5

got=$(od -An -v -tx1 "$CAP" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//')
printf '  note: the app received %s\n' "'$got'"
assert_eq "$got" "1b 5b 31 31 36 3b 36 75" "Cmd+Shift+T reaches the app as Ctrl+Shift+T"
