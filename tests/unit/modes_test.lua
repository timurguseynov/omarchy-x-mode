-- modes.lua is pure, so this runs with plain lua: no Hyprland, no compositor.
local repo = os.getenv("X_MODE_REPO") or "."
local modes = dofile(repo .. "/hypr/x-mode/modes.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    io.stderr:write(string.format("FAIL %s: got %s, want %s\n", name, tostring(got), tostring(want)))
    failures = failures + 1
  end
end

local function fails(name, fn)
  local ok = pcall(fn)
  if ok then
    io.stderr:write(string.format("FAIL %s: expected an error, got none\n", name))
    failures = failures + 1
  end
end

-- A saved workspace file, exactly as omarchy-hyprland-workspace-layout-toggle
-- writes it.
local saved = modes.parse_saved('o.workspace_mode({ workspace = "3", mode = "xmode" })')
check("parse.workspace.id", saved and saved.workspace, 3)
check("parse.workspace.mode", saved and saved.mode, "xmode")

local def = modes.parse_saved('o.workspace_mode({ default = "floating" })')
check("parse.default.mode", def and def.default, "floating")
check("parse.default.no-workspace", def and def.workspace, nil)

check("parse.empty", modes.parse_saved(""), nil)
check("parse.nothing", modes.parse_saved("-- nothing here"), nil)
-- A named workspace reports a negative id and keeps no mode of its own.
check("parse.named-workspace", modes.parse_saved('o.workspace_mode({ workspace = "name:x", mode = "xmode" })'), nil)

-- The state: a workspace's own mode wins over the default, and a workspace
-- without one follows it.
local state = modes.new()
modes.load(state, def)
modes.load(state, saved)
check("get.default", modes.get(state, 1), "floating")
check("get.own", modes.get(state, 3), "xmode")
check("is_xmode.own", modes.is_xmode(state, 3), true)
check("is_xmode.default", modes.is_xmode(state, 1), false)
check("get.unknown-workspace", modes.get(state, "named"), "floating")

modes.set(state, 7, "dwindle")
check("set.workspace", modes.get(state, 7), "dwindle")
modes.set(state, "7", "xmode")
check("set.workspace-string-id", modes.get(state, 7), "xmode")
modes.set(state, 7, nil)
check("set.keeps-on-bad-mode", modes.get(state, 7), "xmode")

-- Ranges, for the window rules that make xmode workspaces float: every xmode id
-- as contiguous [from, to] ranges.
local only = modes.new()
modes.set(only, 1, "xmode")
modes.set(only, 2, "xmode")
modes.set(only, 5, "xmode")
local r = modes.ranges(only)
check("ranges.count", #r, 2)
check("ranges.first", r[1][1] .. "-" .. r[1][2], "1-2")
check("ranges.second", r[2][1] .. "-" .. r[2][2], "5-5")
check("range_matches", table.concat(modes.range_matches(only), ","), "r[1-2],r[5-5]")

check("ranges.none", #modes.ranges(modes.new()), 0)

-- xmode as the default: everything that is not explicitly another mode is in it,
-- which is what the default mode is for.
local all = modes.new()
modes.set_default(all, "xmode")
modes.set(all, 3, "dwindle")
local d = modes.ranges(all)
check("ranges.default.count", #d, 2)
check("ranges.default.first", d[1][1] .. "-" .. d[1][2], "1-2")
check("ranges.default.to-last", d[2][1] .. "-" .. d[2][2], "4-" .. modes.LAST)

-- A default that is not xmode leaves only the explicit ones.
local some = modes.new()
modes.set_default(some, "dwindle")
modes.set(some, 4, "xmode")
check("ranges.explicit-only", modes.ranges(some)[1][1] .. "-" .. modes.ranges(some)[1][2], "4-4")

-- A workspace id that is not a number, or a mode that is not a string, is not a
-- mode: the state is left alone rather than holding something the rules cannot
-- spell.
modes.set(only, "nope", "xmode")
check("set.bad-workspace", #modes.ranges(only), 2)
modes.set(only, 9, "")
check("set.empty-mode", modes.get(only, 9), nil)

if failures > 0 then
  io.stderr:write(string.format("%d failure(s)\n", failures))
  os.exit(1)
end
