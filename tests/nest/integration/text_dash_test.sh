#!/usr/bin/env bash
# The pack's dash key: Option+minus types an em dash, the character a Mac's
# Option layer has on that key. The character cannot come from the keymap the way
# the Mac's does -- the pack's left Option is Alt, the shortcut modifier, not the
# level-3 key that selects a layout's extra characters -- and a virtual keyboard
# cannot inject it either: wtype types through the seat, so the held Option is
# still in the app's modifier state and a terminal reads the dash as Alt+dash and
# prefixes Escape (e2 80 94 arrives as 1b e2 80 94, measured). So the pack sends
# the keymap's own compose sequence for the character, to the focused window,
# with the modifier state the pack sets -- the same send the text chords use,
# which is also what keeps the held Option out of the app.
#
# Two keymaps have to carry the compose key for that, and neither is in the nest
# as it comes up: Hyprland resolves a chord in *its* keymap, and the client
# resolves the synthetic keycode in the keymap of the device that last became the
# seat's -- the test keyboard's. On the live session Omarchy's own input config
# (compose:caps) is in both. So the scenario plants it in the nest's config, and
# hands it to the keyboard tool through XKB_DEFAULT_OPTIONS (the tool builds its
# keymap from the rules and leaves `options` to the environment).
. "$(dirname "$0")/../../lib.sh"

CAP="$NEST_STATE/text-dash.out"

kbd() { XKB_DEFAULT_OPTIONS=compose:caps WAYLAND_DISPLAY="$(nest_display)" "$KEYBOARD_BIN" "$@"; }

capture() { # CLASS
  rm -f "$CAP"
  open_command "$1" foot -a "$1" sh -c "stty raw -echo; cat > '$CAP'"
  nest_ctl dispatch "hl.dsp.focus({ window = 'class:$1' })" >/dev/null
  sleep 0.4
}

received() { od -An -v -tx1 "$CAP" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//'; }

nest_ctl eval "hl.config({ input = { kb_options = 'compose:caps' } })" >/dev/null

capture dashcompose
kbd alt+minus
sleep 0.7
printf '  note: Option+minus with a compose key received %s\n' "'$(received)'"
assert_eq "$(received)" "e2 80 94" "with a compose key Option+minus types an em dash"

# With no compose key in the keymap there is nothing to send: the key stays the
# app's, rather than dispatching Multi_key at a keymap that has no such key
# (a Hyprland error on every press), and the app gets the plain Option+minus it
# would have got had the pack never bound the key.
nest_ctl eval "hl.config({ input = { kb_options = 'shift:both_capslock_cancel' } })" >/dev/null

capture dashnocompose
kbd alt+minus
sleep 0.7
printf '  note: Option+minus with no compose key received %s\n' "'$(received)'"
assert_eq "$(received)" "1b 2d" "with no compose key the key is left to the app"
