-- supermap.lua is pure, so this runs with plain lua: no Hyprland, no hyprctl.
local repo = os.getenv("X_MODE_REPO") or "."
local supermap = dofile(repo .. "/hypr/x-mode/supermap.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    io.stderr:write(string.format("FAIL %s: got %s, want %s\n", name, tostring(got), tostring(want)))
    failures = failures + 1
  end
end

-- The plan is a list; index it as "<key>/<plain|shift>" for the checks.
local function index(plan)
  local set = {}
  for _, b in ipairs(plan) do
    set[b.key .. "/" .. (b.shift and "shift" or "plain")] = true
  end
  return set
end

-- The keysym list has to carry the keys the app shortcuts need, in the spelling
-- bind strings use.
local function has_key(list, key)
  for _, k in ipairs(list) do
    if k == key then
      return true
    end
  end
  return false
end
check("keys.letter", has_key(supermap.KEYS, "T"), true)
check("keys.nav", has_key(supermap.KEYS, "LEFT"), true)
check("keys.punct", has_key(supermap.KEYS, "comma"), true)
-- The keycode `send_shortcut` sends for a name, so a Cyrillic layout (where the
-- name does not resolve) still gets the physical key.
check("code.W", supermap.key_code("W"), 25)
check("code.digit", supermap.key_code("1"), 10)
check("code.tab", supermap.key_code("TAB"), 23)
check("code.unknown", supermap.key_code("nope"), nil)
check("code.nil", supermap.key_code(nil), nil)

-- A bind table shaped like `hyprctl binds` prints them:
--   SUPER + T           occupied (Omarchy)
--   SUPER + SHIFT + N   occupied
--   SUPER + ALT + LEFT  a different modmask, so LEFT stays free
--   SUPER + H           only inside a submap, so free at the top level
--   SUPER + L           one of ours (the description marks it), so free as well
--   SUPER + code:20     the minus key, written by keycode
--   SUPER + code:10     and its Shift form: Omarchy's workspace binds are
--                       written this way, so SUPER+1 is taken even though no
--                       bind above names the key "1"
local raw = [[
bind
	modmask: 64
	submap: 
	key: T
	keycode: 0
	catchall: false
	description: 
	dispatcher: exec
	arg: x

bind
	modmask: 65
	submap: 
	key: N
	keycode: 0
	catchall: false
	description: 
	dispatcher: exec
	arg: x

bind
	modmask: 72
	submap: 
	key: LEFT
	keycode: 0
	catchall: false
	description: 
	dispatcher: exec
	arg: x

bind
	modmask: 64
	submap: resize
	key: H
	keycode: 0
	catchall: false
	description: 
	dispatcher: submap
	arg: reset

bind
	modmask: 64
	submap: 
	key: L
	keycode: 0
	catchall: false
	description: x-mode-super-ctrl L
	dispatcher: __lua
	arg: 1

bind
	modmask: 64
	submap: 
	key: SUPER + code:20
	keycode: 0
	catchall: false
	description: 
	dispatcher: __lua
	arg: 2

bind
	modmask: 64
	submap: 
	key: SUPER + code:10
	keycode: 0
	catchall: false
	description: 
	dispatcher: __lua
	arg: 3

bind
	modmask: 65
	submap: 
	key: SUPER + code:10
	keycode: 0
	catchall: false
	description: 
	dispatcher: __lua
	arg: 4
]]

local set = index(supermap.plan(raw))
check("plan.t.occupied", set["T/plain"], nil)
check("plan.t.shift.free", set["T/shift"], true)
check("plan.n.occupied", set["N/shift"], nil)
check("plan.n.plain.free", set["N/plain"], true)
check("plan.nav.other-mods", set["LEFT/plain"], true)
check("plan.submap.ignored", set["H/plain"], true)
check("plan.own.ignored", set["L/plain"], true)
check("plan.code.minus", set["minus/plain"], nil)
check("plan.code.digit", set["1/plain"], nil)
check("plan.code.digit.shift", set["1/shift"], nil)

-- No binds at all: every key is free.
local empty_plan = index(supermap.plan("bind\n\tmodmask: 4\n\tkey: X\n\n"))
check("plan.empty.t", empty_plan["T/plain"], true)
check("plan.empty.t.shift", empty_plan["T/shift"], true)
check("plan.empty.punct", empty_plan["comma/plain"], true)

-- The digits are never planned, even when nothing holds them: they belong to
-- Omarchy's workspaces, and with the workspaces on the F keys the pack binds
-- them itself so the focused app decides. Planning one here would put two
-- handlers on the same key.
check("plan.empty.digit", empty_plan["1/plain"], nil)
check("plan.empty.digit.ten", empty_plan["0/plain"], nil)
check("plan.empty.digit.shift", empty_plan["1/shift"], nil)

-- Punctuation gets no Shift variant: the shifted keysym is a different key, so
-- the bind would never match.
check("plan.punct.no-shift", empty_plan["comma/shift"], nil)

-- Junk input plans nothing rather than raising.
check("plan.junk", #supermap.plan("not a bind table"), 0)

-- Occupied Super keys the panel can steal: in KEYS, Super or Super+Shift, not
-- a generated super-ctrl bind, not a submap, not the digits (those move to F
-- keys in the main panel), not Super+W (its own toggle). A foreign __lua bind
-- cannot be replayed, so stealable() drops it unless the pack wraps that key
-- itself (Q, Tab).
check("id.plain", supermap.key_id("Q", false), "Q")
check("id.shift", supermap.key_id("TAB", true), "SHIFT+TAB")
check("canon.q", supermap.canonical_id("q"), "Q")
check("canon.shift-tab", supermap.canonical_id("shift+tab"), "SHIFT+TAB")
check("canon.bad", supermap.canonical_id("mouse:272"), nil)

local occ_raw = [[
bind
	modmask: 64
	submap: 
	key: T
	keycode: 0
	catchall: false
	description: Toggle floating
	dispatcher: exec
	arg: x

bind
	modmask: 64
	submap: 
	key: W
	keycode: 0
	catchall: false
	description: Close window
	dispatcher: __lua
	arg: 1

bind
	modmask: 64
	submap: 
	key: Q
	keycode: 0
	catchall: false
	description: Close app
	dispatcher: __lua
	arg: 2

bind
	modmask: 64
	submap: 
	key: F
	keycode: 0
	catchall: false
	description: Full screen
	dispatcher: __lua
	arg: 7

bind
	modmask: 64
	submap: 
	key: C
	keycode: 0
	catchall: false
	description: Universal copy
	dispatcher: __lua
	arg: 3

bind
	modmask: 64
	submap: 
	key: B
	keycode: 0
	catchall: false
	description: Browser
	dispatcher: exec
	arg: omarchy-launch-browser

bind
	modmask: 64
	submap: 
	key: SUPER + code:10
	keycode: 0
	catchall: false
	description: Switch to workspace 1
	dispatcher: workspace
	arg: 1

bind
	modmask: 64
	submap: 
	key: L
	keycode: 0
	catchall: false
	description: x-mode-super-ctrl L
	dispatcher: __lua
	arg: 4

bind
	modmask: 64
	submap: resize
	key: H
	keycode: 0
	catchall: false
	description: 
	dispatcher: submap
	arg: reset

bind
	modmask: 65
	submap: 
	key: TAB
	keycode: 0
	catchall: false
	description: Focus on previous window
	dispatcher: __lua
	arg: 5

bind
	modmask: 64
	submap: 
	key: K
	keycode: 0
	catchall: false
	description: x-mode-super-steal K Keybindings
	dispatcher: __lua
	arg: 6
]]

local function by_id(list)
  local set = {}
  for _, e in ipairs(list) do
    set[e.id] = e
  end
  return set
end

local occ = by_id(supermap.occupied_list(occ_raw))
check("occ.t", occ["T"] ~= nil, true)
check("occ.t.disp", occ["T"].dispatcher, "exec")
check("occ.w.skip", occ["W"], nil)
check("occ.digit.skip", occ["1"], nil)
check("occ.own-ctrl.skip", occ["L"], nil)
check("occ.submap.skip", occ["H"], nil)
check("occ.q", occ["Q"] ~= nil, true)
check("occ.f", occ["F"] ~= nil, true)
check("occ.c", occ["C"] ~= nil, true)
check("occ.b", occ["B"] ~= nil, true)
check("occ.shift-tab", occ["SHIFT+TAB"] ~= nil, true)
check("occ.steal-wrap", occ["K"] ~= nil, true)
check("occ.t.label", occ["T"].label, "⌘+T")
check("occ.shift-tab.label", occ["SHIFT+TAB"].label, "⌘+⇧+Tab")
check("pretty.comma", supermap.label("comma", false), "⌘+,")
check("pretty.esc", supermap.label("ESCAPE", false), "⌘+Esc")
check("pretty.enter", supermap.label("RETURN", false), "⌘+Enter")
check("pretty.bksp", supermap.label("BACKSPACE", false), "⌘+⌫")
check("pretty.left", supermap.label("LEFT", false), "⌘+←")
check("pretty.pgup", supermap.label("PAGE_UP", false), "⌘+PgUp")

local steal = by_id(supermap.stealable(occ_raw, { Q = true, TAB = true }))
check("steal.t", steal["T"] ~= nil, true)
check("steal.b", steal["B"] ~= nil, true)
check("steal.q", steal["Q"] ~= nil, true)
check("steal.shift-tab", steal["SHIFT+TAB"] ~= nil, true)
check("steal.f.foreign-lua", steal["F"], nil)
check("steal.c.foreign-lua", steal["C"], nil)
local steal_f = by_id(supermap.stealable(occ_raw, { Q = true, TAB = true, F = true }))
check("steal.f.own", steal_f["F"] ~= nil, true)
check("steal.k.wrap", steal["K"] ~= nil, true)
check("steal.k.desc", steal["K"].description, "Keybindings")

local json = supermap.occupied_json(supermap.stealable(occ_raw, { Q = true, TAB = true }))
check("json.has-q", json:find('"id":"Q"', 1, true) ~= nil, true)
check("json.no-c", json:find('"id":"C"', 1, true) == nil, true)
check("json.escapes", supermap.occupied_json({ { id = "Q", key = "Q", shift = false, label = "Super+Q", description = 'say "hi"' } }):find('\\"hi\\"') ~= nil, true)

local with_exec = by_id(supermap.stealable(occ_raw, { Q = true, TAB = true }, { C = "x" }))
check("steal.c.exec-map", with_exec["C"] ~= nil, true)

local omarchy = supermap.parse_omarchy_binds([[
o.bind("SUPER + K", "Keybindings", "omarchy-menu-keybindings")
o.bind("SUPER + RETURN", "Terminal", { omarchy = "terminal" })
o.bind("SUPER + SHIFT + RETURN", "Browser", { omarchy = "browser" })
o.bind("SUPER + ALT + K", "Tmux keybindings", "omarchy-menu-tmux-keybindings")
o.bind("SUPER + C", "Universal copy", universal_clipboard_shortcut("CTRL", "C"))
o.bind_toggle("SUPER + SHIFT + SPACE", "Toggle top bar", "bar")
o.bind("SUPER + SHIFT + P", "Google Photos", { webapp = "https://photos.google.com/", focus = true })
o.bind("SUPER + SHIFT + A", "ChatGPT", { webapp = "https://chatgpt.com" })
o.bind("SUPER + SHIFT + O", "Obsidian", { launch = "obsidian", focus = "^obsidian$" })
o.bind("SUPER + SHIFT + W", "Omawrite", { launch = "omawrite" })
o.bind("SUPER + SHIFT + D", "Docker", { tui = "omarchy-launch-docker-tui" })
o.bind("SUPER + SHIFT + U", "Music TUI", { tui = "cliamp", focus = true })
o.bind("SUPER + SHIFT + Q", "Quoted", { launch = "tea's" })
]])
check("omarchy.k", omarchy["K"], "omarchy-menu-keybindings")
check("omarchy.return", omarchy["RETURN"], "omarchy-launch-terminal")
check("omarchy.shift-return", omarchy["SHIFT+RETURN"], "omarchy-launch-browser")
check("omarchy.alt.skip", omarchy["SHIFT+K"], nil)
check("omarchy.c.fn.skip", omarchy["C"], nil)
check("omarchy.toggle", omarchy["SHIFT+SPACE"], "omarchy-toggle-bar")

-- The other table dispatchers Omarchy's helpers build a command for. Without
-- these the key never reaches the panel's steal list: it stays an opaque
-- __lua callback, so nothing can replay it after an unbind.
check("omarchy.webapp.focus", omarchy["SHIFT+P"], "omarchy-launch-or-focus-webapp 'Google Photos' 'https://photos.google.com/'")
check("omarchy.webapp", omarchy["SHIFT+A"], "omarchy-launch-webapp 'https://chatgpt.com'")
check("omarchy.launch.focus", omarchy["SHIFT+O"], "omarchy-launch-or-focus '^obsidian$' 'uwsm-app -- obsidian'")
check("omarchy.launch", omarchy["SHIFT+W"], "uwsm-app -- 'omawrite'")
check("omarchy.tui", omarchy["SHIFT+D"], "omarchy-launch-tui 'omarchy-launch-docker-tui'")
check("omarchy.tui.focus", omarchy["SHIFT+U"], "omarchy-launch-or-focus-tui 'cliamp'")
check("omarchy.quote", omarchy["SHIFT+Q"], "uwsm-app -- 'tea'\\''s'")

if failures > 0 then
  os.exit(1)
end
print("supermap ok")
