#!/usr/bin/env bash
# Cmd+A is "select all" on macOS, and on this desktop it was Omarchy's bind, which
# sends the chord by *name* ("CTRL", "A"). Hyprland resolves a name in the
# keyboard's *active group*: with a Russian group active there is no Latin A on the
# A key, so the dispatch fails -- "runtime error in lua, send_key_state: key not
# found" -- and the select never reaches the app. That press is the report this
# scenario comes from, and the pack answers it the way it already answers
# Cmd+C/V/X: it owns the key and sends it by keycode, which is the physical key
# whatever the group says.
#
# The nest loads no Omarchy bindings, so her bind is planted the way her file writes
# it, in the nest's permanent-toggle directory (nest.lua sources those *before* the
# pack, so the pack's unbind is the one that lands last -- the order the real
# desktop has). A marker bind on the same key says whether hers is still in force:
# Hyprland runs every bind that matches, so if the pack stopped taking the key, the
# marker fires and her name-based send is what the app gets.
#
# The press asks the keyboard tool for a us,ru keymap left in group 1 (`-l us,ru
# -g 1`), which is the state the report came from: the key event matches the bind
# (matching reads the compositor's own keymap, first group), while a send that
# names "A" resolves against the group the keyboard is actually in.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"
CAP="$NEST_STATE/select_all.out"
TOGGLES="$NEST_STATE/home/.local/state/omarchy/toggles/hypr"
MARKER="$NEST_STATE/state/select-all-her-bind-fired"

received() { od -An -v -tx1 "$CAP" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//'; }

mkdir -p "$TOGGLES" "$NEST_STATE/state"
cat > "$TOGGLES/select-all.lua" <<LUA
-- Omarchy's select all, as her default/hypr/bindings/clipboard.lua writes it: the
-- key by name, in its own down/up pair. The second bind is the marker: it must not
-- survive the pack's own binding of the key.
local function send_shortcut_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end
o.bind("SUPER + A", "Select all", send_shortcut_once("CTRL", "A"))
o.bind("SUPER + A", "Select all marker", function()
  hl.exec_cmd("touch '$MARKER'")
end)
LUA

printf '%s\n' '{"options":{},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.8

rm -f "$CAP" "$MARKER"
open_command kitty kitty sh -c "stty raw -echo; cat > '$CAP'"
wait_until 3 '[ -e "$CAP" ]' || fail "the capture window did not open"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3

# The chord it sends is the app's own: byte for byte what a physical Ctrl+A sends
# with the same group active. Her name-based send reaches nothing here -- Hyprland
# refuses it -- so before the pack owned the key these bytes do not arrive, which
# is exactly what the report saw: the key did nothing.
key -l us,ru -g 1 ctrl+a
sleep 0.4
base="$(received)"
[ -n "$base" ] || fail "the capture window received nothing from Ctrl+A"
key -l us,ru -g 1 super+a
sleep 0.5
assert_eq "$(received)" "$base $base" "Cmd+A reaches the app as what Ctrl+A sends"

# And her bind was replaced, not joined: the pack's own Cmd+A is the one the key
# has.
assert_eq "$(bind_count_desc "Select all marker" 64)" 0 "her bind was replaced, not joined"
assert_eq "$([ -f "$MARKER" ] && echo yes || echo no)" no \
  "her bind does not fire: the pack's own Cmd+A is the one the key has"
