-- textkeys.lua is pure, so this runs with plain lua: no Hyprland, no hyprctl.
-- It holds the macOS text chords (the Cocoa ones: Cmd+arrow, Option+arrow,
-- Option+Backspace, ...) and what has to be sent instead in each context: a
-- terminal (readline/zle: Alt+B, Ctrl+W, Ctrl+U) or a GUI toolkit (Ctrl+arrow,
-- Ctrl+Backspace, Shift+Home...). Getting that split wrong is invisible until
-- someone is in a shell, so it is pinned here.
local repo = os.getenv("X_MODE_REPO") or "."
local textkeys = dofile(repo .. "/hypr/x-mode/textkeys.lua")
-- The keycodes the compositor sends a chord as, so a chord can be checked to be
-- one the pack can spell at all.
local supermap = dofile(repo .. "/hypr/x-mode/supermap.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    io.stderr:write(string.format("FAIL %s: got %s, want %s\n", name, tostring(got), tostring(want)))
    failures = failures + 1
  end
end

-- A chord list as "MODS+key" strings, so a check reads like the binding does.
-- Mods are spelled the way send_shortcut takes them ("CTRL SHIFT"), which is
-- not the way bind strings spell them ("CTRL + SHIFT +").
local function spell(list)
  local out = {}
  for i, c in ipairs(list or {}) do
    out[i] = (c.mods ~= "" and c.mods:gsub(" ", "+") .. "+" or "") .. c.key
  end
  return table.concat(out, " ")
end

local by_id = {}
for _, e in ipairs(textkeys.plan()) do
  by_id[e.id] = e
end

check("plan.count", #textkeys.plan() > 0, true)

-- Every entry has to spell out both contexts: a missing one would silently
-- fall back to the other, which is how Ctrl+Backspace ends up in a shell.
for _, e in ipairs(textkeys.plan()) do
  check("entry." .. e.id .. ".keys", type(e.keys) == "string" and e.keys ~= "", true)
  check("entry." .. e.id .. ".label", type(e.label) == "string" and e.label ~= "", true)
  check("entry." .. e.id .. ".terminal", type(e.terminal) == "table", true)
  check("entry." .. e.id .. ".gui", type(e.gui) == "table", true)
end

-- Two entries on one key would mean one of them never fires.
local seen = {}
for _, e in ipairs(textkeys.plan()) do
  check("unique." .. e.keys, seen[e.keys], nil)
  seen[e.keys] = true
end

-- Cmd+arrow is line start/end on macOS. Home/End is what both a terminal and a
-- toolkit understand, so there is nothing to split here.
check("line.terminal", spell(by_id["SUPER+LEFT"].terminal), "HOME")
check("line.gui", spell(by_id["SUPER+LEFT"].gui), "HOME")
check("line.right", spell(by_id["SUPER+RIGHT"].gui), "END")
check("line.up", spell(by_id["SUPER+UP"].gui), "CTRL+HOME")
check("line.down", spell(by_id["SUPER+DOWN"].gui), "CTRL+END")
check("select.line", spell(by_id["SUPER+SHIFT+LEFT"].gui), "SHIFT+HOME")
check("select.doc", spell(by_id["SUPER+SHIFT+UP"].gui), "CTRL+SHIFT+HOME")

-- Cmd+Backspace deletes to the beginning of the line. A shell cannot do that
-- with Shift+Home (readline does not bind it), so it gets Ctrl+U; the GUI path
-- builds the selection and deletes it.
check("kill.line.terminal", spell(by_id["SUPER+BACKSPACE"].terminal), "CTRL+U")
check("kill.line.gui", spell(by_id["SUPER+BACKSPACE"].gui), "SHIFT+HOME BACKSPACE")
check("kill.end.terminal", spell(by_id["SUPER+DELETE"].terminal), "CTRL+K")
check("kill.end.gui", spell(by_id["SUPER+DELETE"].gui), "SHIFT+END DELETE")

-- Option+arrow is word motion. A terminal wants readline's own Meta chord; a
-- GUI toolkit wants Ctrl+arrow.
check("word.left.terminal", spell(by_id["ALT+LEFT"].terminal), "ALT+B")
check("word.left.gui", spell(by_id["ALT+LEFT"].gui), "CTRL+LEFT")
check("word.right.terminal", spell(by_id["ALT+RIGHT"].terminal), "ALT+F")
check("word.right.gui", spell(by_id["ALT+RIGHT"].gui), "CTRL+RIGHT")

-- Option+Backspace deletes a word back. Ctrl+Backspace is *one character* to
-- readline, so the terminal path has to be Ctrl+W.
check("del.word.terminal", spell(by_id["ALT+BACKSPACE"].terminal), "CTRL+W")
check("del.word.gui", spell(by_id["ALT+BACKSPACE"].gui), "CTRL+BACKSPACE")

-- Option+Delete deletes a word forward. readline calls it Alt+D and does not
-- bind the Option+Delete sequence at all (it leaks a "~" without this).
check("del.forward.terminal", spell(by_id["ALT+DELETE"].terminal), "ALT+D")
check("del.forward.gui", spell(by_id["ALT+DELETE"].gui), "CTRL+DELETE")

-- Selecting by word: readline has no selection at all, so a terminal gets
-- nothing and the key is left alone; a toolkit gets its own chord.
check("select.word.terminal", #by_id["ALT+SHIFT+LEFT"].terminal, 0)
check("select.word.gui", spell(by_id["ALT+SHIFT+LEFT"].gui), "CTRL+SHIFT+LEFT")

-- Back/Forward. A terminal never gets them; anything else sends the chord the
-- app already uses for it (a browser's Alt+Left is Back).
check("back.terminal", #by_id["SUPER+bracketleft"].terminal, 0)
check("back.gui", spell(by_id["SUPER+bracketleft"].gui), "ALT+LEFT")
check("forward.gui", spell(by_id["SUPER+bracketright"].gui), "ALT+RIGHT")

-- Nothing may send the chord it was bound to back out again: a synthetic chord
-- does not re-enter the bind table, but re-sending the same key is a sign the
-- entry is a no-op that should not be bound at all.
for _, e in ipairs(textkeys.plan()) do
  local target = e.keys:gsub("%s+", "")
  check("loop." .. e.id, spell(e.gui) == target or spell(e.terminal) == target, false)
end

-- The typography: on a Mac the layout has `⌥-` as a dash, and the pack spells
-- the character with the keymap's compose sequence instead (the key it owns is
-- the left Option, which is Alt -- the shortcut modifier, not the level-3 key
-- that selects a layout's extra characters). `-` is the minus key in every
-- layout, so the em dash is the same sequence wherever the desktop is; the en
-- dash's sequence ends in `.`, which a layout may put behind Shift (the Russian
-- one does, on 7), so it is not here.
check("dash.gui", spell(by_id["ALT+minus"].gui), "Multi_key minus minus minus")
check("dash.terminal", spell(by_id["ALT+minus"].terminal), "Multi_key minus minus minus")
check("dash.needs", by_id["ALT+minus"].needs, "compose")

-- Every chord is sent as a keycode, so the entry has to be a key the pack has
-- one for; the compose key is the one name it has none for (which key carries
-- Multi_key is the user's input option, so there is no code to hard-code).
-- Anything else here would be a typo that turns into a Hyprland error at press
-- time instead of the no-op it used to be.
for _, e in ipairs(textkeys.plan()) do
  for _, list in ipairs({ e.terminal, e.gui }) do
    for _, c in ipairs(list) do
      check("chord.known." .. e.id .. "." .. c.key, c.key == "Multi_key" or supermap.key_code(c.key) ~= nil, true)
    end
  end
end

-- compose_key() decides whether the pack can spell those characters at all: it
-- is the user's input option, and Omarchy's own default is compose:caps.
check("compose.caps", textkeys.compose_key("compose:caps"), true)
check("compose.mixed", textkeys.compose_key("shift:both_capslock_cancel,compose:menu"), true)
check("compose.multikey", textkeys.compose_key("lv3:ralt_switch_multikey"), true)
check("compose.none", textkeys.compose_key("shift:both_capslock_cancel"), false)
check("compose.empty", textkeys.compose_key(""), false)
check("compose.nil", textkeys.compose_key(nil), false)

-- chords(id, is_terminal) is what the compositor calls at press time.
check("chords.terminal", spell(textkeys.chords("ALT+LEFT", true)), "ALT+B")
check("chords.gui", spell(textkeys.chords("ALT+LEFT", false)), "CTRL+LEFT")
check("chords.missing", textkeys.chords("NOPE+NOPE", false), nil)

-- A terminal with nothing to send (no selection in readline) has to be
-- distinguishable from an unknown id: the first passes the key through, the
-- second is a bug in the caller.
check("empty.terminal", #textkeys.chords("ALT+SHIFT+LEFT", true), 0)

-- The tag Omarchy puts on terminals; anything else is a GUI app.
check("is_terminal.tagged", textkeys.is_terminal({ "terminal" }), true)
check("is_terminal.dynamic", textkeys.is_terminal({ "terminal*" }), true)
check("is_terminal.other", textkeys.is_terminal({ "chromium-based-browser" }), false)
check("is_terminal.none", textkeys.is_terminal(nil), false)
check("is_terminal.empty", textkeys.is_terminal({}), false)

if failures > 0 then
  os.exit(1)
end
print("textkeys ok")
