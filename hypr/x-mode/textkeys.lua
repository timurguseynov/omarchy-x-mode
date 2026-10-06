-- The macOS text chords, and what each one has to send in the app that
-- receives it. This is the pack playing the part the Mac plays itself: on
-- macOS the text system is the OS's, so Cmd+Left is the start of the line in
-- every app, and Option+Backspace deletes a word in every app. Linux has no
-- such layer: each toolkit invented its own chords, and the terminal invented
-- readline's.
--
-- So every entry carries two targets, and the compositor picks one by looking
-- at the focused window (is_terminal). The split is not cosmetic:
--
--   * Ctrl+Backspace is a *word* delete in GTK/Qt and a *single character* in
--     readline, so the shell path has to be Ctrl+W.
--   * readline has no Shift+Home (it is unbound, and feeding it one leaves
--     garbage in the line), so Cmd+Backspace is Ctrl+U in a shell.
--   * Option+Delete is not bound by anything at all on Linux -- readline has
--     the same function on Alt+D, and the sequence otherwise leaks a "~".
--   * readline has no selection, so Option+Shift+arrow has nothing to send in
--     a terminal and the key is left to the app.
--
-- A target is a list of chords, sent in order: { { mods = "CTRL", key = "U" } }.
-- The key is the name `send_shortcut` takes (or "code:N"), and mods is its
-- "CTRL SHIFT" spelling. An empty list means "nothing to do here" and the
-- caller passes the key through untouched.
--
-- Pure data plus pure lookups (tests/unit/textkeys_test.lua); binding and
-- sending live in x-mode.lua.
local M = {}

local function chord(mods, key)
  return { mods = mods, key = key }
end

-- Cmd+arrow moves by line and document; the Shift form extends the selection.
-- Home/End satisfies both a toolkit and a shell (readline binds it, and so do
-- zle and fish), so these need no per-context split at all.
local LINE = {
  { id = "SUPER+LEFT", keys = "SUPER + LEFT", label = "Start of line", same = { chord("", "HOME") } },
  { id = "SUPER+RIGHT", keys = "SUPER + RIGHT", label = "End of line", same = { chord("", "END") } },
  { id = "SUPER+UP", keys = "SUPER + UP", label = "Start of document", same = { chord("CTRL", "HOME") } },
  { id = "SUPER+DOWN", keys = "SUPER + DOWN", label = "End of document", same = { chord("CTRL", "END") } },
  { id = "SUPER+SHIFT+LEFT", keys = "SUPER + SHIFT + LEFT", label = "Select to start of line", same = { chord("SHIFT", "HOME") } },
  { id = "SUPER+SHIFT+RIGHT", keys = "SUPER + SHIFT + RIGHT", label = "Select to end of line", same = { chord("SHIFT", "END") } },
  { id = "SUPER+SHIFT+UP", keys = "SUPER + SHIFT + UP", label = "Select to start of document", same = { chord("CTRL SHIFT", "HOME") } },
  { id = "SUPER+SHIFT+DOWN", keys = "SUPER + SHIFT + DOWN", label = "Select to end of document", same = { chord("CTRL SHIFT", "END") } },
}

-- Option+arrow: word motion. A shell wants readline's own Meta chords (they
-- work in zle and fish too); a toolkit wants Ctrl+arrow.
local WORD = {
  {
    id = "ALT+LEFT", keys = "ALT + LEFT", label = "Word left",
    terminal = { chord("ALT", "B") },
    gui = { chord("CTRL", "LEFT") },
  },
  {
    id = "ALT+RIGHT", keys = "ALT + RIGHT", label = "Word right",
    terminal = { chord("ALT", "F") },
    gui = { chord("CTRL", "RIGHT") },
  },
  {
    id = "ALT+SHIFT+LEFT", keys = "ALT + SHIFT + LEFT", label = "Select word left",
    -- readline has no selection to extend.
    terminal = {},
    gui = { chord("CTRL SHIFT", "LEFT") },
  },
  {
    id = "ALT+SHIFT+RIGHT", keys = "ALT + SHIFT + RIGHT", label = "Select word right",
    terminal = {},
    gui = { chord("CTRL SHIFT", "RIGHT") },
  },
}

-- Deletions. Both Cmd forms need the split: a shell kills the line with its
-- own chord, and readline cannot Shift+Home.
local DELETE = {
  {
    id = "SUPER+BACKSPACE", keys = "SUPER + BACKSPACE", label = "Delete to start of line",
    terminal = { chord("CTRL", "U") },
    gui = { chord("SHIFT", "HOME"), chord("", "BACKSPACE") },
  },
  {
    id = "SUPER+DELETE", keys = "SUPER + DELETE", label = "Delete to end of line",
    terminal = { chord("CTRL", "K") },
    gui = { chord("SHIFT", "END"), chord("", "DELETE") },
  },
  {
    id = "ALT+BACKSPACE", keys = "ALT + BACKSPACE", label = "Delete word backward",
    terminal = { chord("CTRL", "W") },
    gui = { chord("CTRL", "BACKSPACE") },
  },
  {
    id = "ALT+DELETE", keys = "ALT + DELETE", label = "Delete word forward",
    terminal = { chord("ALT", "D") },
    gui = { chord("CTRL", "DELETE") },
  },
}

-- Cmd+[ / Cmd+] are Back/Forward on macOS. On Linux Back is Alt+Left, and
-- Option+arrow is word motion from here on, so this is where Back lives now.
-- A shell has no Back to go to, and readline has no history for these to mean
-- anything, so the key is left to the app there.
local NAVIGATE = {
  {
    id = "SUPER+bracketleft", keys = "SUPER + bracketleft", label = "Back",
    terminal = {},
    gui = { chord("ALT", "LEFT") },
  },
  {
    id = "SUPER+bracketright", keys = "SUPER + bracketright", label = "Forward",
    terminal = {},
    gui = { chord("ALT", "RIGHT") },
  },
}

local PLAN = {}
local BY_ID = {}

local function add(entry, fallback)
  local terminal = entry.terminal
  local gui = entry.gui
  if fallback ~= nil then
    terminal = fallback
    gui = fallback
  end
  local e = {
    id = entry.id,
    keys = entry.keys,
    label = entry.label,
    terminal = terminal,
    gui = gui,
  }
  PLAN[#PLAN + 1] = e
  BY_ID[e.id] = e
end

for _, e in ipairs(LINE) do
  add(e, e.same)
end
for _, e in ipairs(WORD) do
  add(e)
end
for _, e in ipairs(DELETE) do
  add(e)
end
for _, e in ipairs(NAVIGATE) do
  add(e)
end

-- The whole set, in bind order. Read-only as far as callers are concerned.
function M.plan()
  return PLAN
end

-- What to send for one chord in this context. An empty list means the app gets
-- the key as it was; nil means the id is not in the plan (a caller's typo).
function M.chords(id, is_terminal)
  local e = BY_ID[id]
  if e == nil then
    return nil
  end
  if is_terminal then
    return e.terminal
  end
  return e.gui
end

-- Omarchy tags terminal windows "terminal" (see default/hypr/apps/terminals.lua),
-- and a tag it adds itself is dynamic and carries a trailing "*". A window
-- without the tag has no tags at all, and Hyprland's answer is the falsey
-- proxy under Omarchy's keybindings scan, so a non-list is not walked.
function M.is_terminal(tags)
  if type(tags) ~= "table" or #tags == 0 then
    return false
  end
  for _, tag in ipairs(tags) do
    if tostring(tag):gsub("%*$", "") == "terminal" then
      return true
    end
  end
  return false
end

return M
