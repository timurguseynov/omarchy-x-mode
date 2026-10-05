#!/usr/bin/env bash
# The universal clipboard (Cmd+C/V/X) is the pack's own, and it sends the chord by
# *keycode*. Omarchy's version sends it by name ("C", "Insert"), and Hyprland
# resolves a name in the *active* layout: with a Russian group active there is no
# Latin C on the C key, so the dispatch fails -- "runtime error in lua,
# send_key_state: key not found" -- and the copy never reaches the app. It works
# again once the name has been resolved once and cached, which is why it only bites
# sometimes.
#
# The nest loads no Omarchy bindings, so her bind is planted the way her file writes
# it, in the nest's permanent-toggle directory (nest.lua sources those *before* the
# pack, so the pack's unbind is the one that lands last -- the order the real
# desktop has). A marker bind on the same key says whether hers is still in force:
# Hyprland runs every bind that matches, so if the pack stopped taking the key, the
# marker fires and her name-based send is what the app gets.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"
CAP="$NEST_STATE/clipboard.out"
TOGGLES="$NEST_STATE/home/.local/state/omarchy/toggles/hypr"
MARKER="$NEST_STATE/state/clipboard-her-bind-fired"

received() { od -An -v -tx1 "$CAP" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//'; }

mkdir -p "$TOGGLES" "$NEST_STATE/state"
cat > "$TOGGLES/clipboard.lua" <<LUA
-- Omarchy's universal clipboard, as her default/hypr/bindings/clipboard.lua writes
-- it: the key by name, in its own down/up pair. The second bind is the marker: it
-- must not survive the pack's own binding of the key.
local function send_shortcut_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end
o.bind("SUPER + C", "Universal copy", send_shortcut_once("CTRL", "C"))
o.bind("SUPER + C", "Clipboard marker", function()
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

# Her bind was replaced, not joined: the pack's own Cmd+C is the one the key has.
assert_eq "$(bind_count_desc "Clipboard marker" 64)" 0 "her bind was replaced, not joined"

# The chord it sends is the app's own copy: byte for byte what a physical Ctrl+C
# sends. The same press would have fired her marker if her bind were still there.
key ctrl+c
sleep 0.4
base="$(received)"
key super+c
sleep 0.5
assert_eq "$(received)" "$base $base" "Cmd+C reaches the app as what Ctrl+C sends"
assert_eq "$([ -f "$MARKER" ] && echo yes || echo no)" no \
  "her bind does not fire: the pack's own Cmd+C is the one the key has"
