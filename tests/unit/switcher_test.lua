-- The switcher row: which classes it lists, in which order, and the line the shell
-- reads. No compositor, no Quickshell.
local repo = os.getenv("X_MODE_REPO") or "."
local switcher = dofile(repo .. "/hypr/x-mode/switcher.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
  end
end

local windows = {
  { class = "foot", address = "a1", focus_history_id = 5 },
  { class = "kitty", address = "a2", focus_history_id = 1 },
  { class = "foot", address = "a3", focus_history_id = 2 },
  { class = "", address = "a4", focus_history_id = 0 },
}

-- With no remembered order the row follows the compositor: the smallest
-- focus_history_id is the most recent, so kitty (1) leads and foot (5, or 2 for its
-- newer window) follows.
local by_focus = switcher.class_entries(windows, {})
check("entries.count", #by_focus, 2)
check("entries.focus-first", by_focus[1].cls, "kitty")
check("entries.uses-most-recent-window", by_focus[2].addr, "a3")

-- The remembered order wins over the focus counter, and it is passed as the array
-- mru.sort reads through ipairs: foot first here, though the compositor says kitty.
local entries = switcher.class_entries(windows, { "foot", "kitty" })
check("entries.mru-first", entries[1].cls, "foot")
check("entries.mru-second", entries[2].cls, "kitty")
check("entries.mru-uses-most-recent-window", entries[1].addr, "a3")

-- A class with no remembered order goes after the ordered ones, and an empty class
-- is not a row at all.
local ordered = switcher.class_entries({ { class = "zed", address = "b1", focus_history_id = 9 } }, {})
check("entries.unknown-class-still-listed", #ordered, 1)
check("entries.none", #switcher.class_entries({ { class = "", address = "c1" } }, {}), 0)

-- The tokens carry the window address, so two windows of one class stay apart.
local tokens = switcher.tokens({ { cls = "foot", addr = "a1" }, { cls = "kitty", addr = "a2" } })
check("tokens.count", #tokens, 2)
check("tokens.first", tokens[1], "foot|a1")

check("line.show", switcher.show_line("foot", tokens), "show foot foot|a1 kitty|a2")
check("line.show-no-tokens", switcher.show_line("foot", {}), "show foot ")
check("line.hide", switcher.hide_line(), "hide")

if failures > 0 then
  os.exit(1)
end
print("switcher ok")
