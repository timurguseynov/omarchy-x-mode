-- Who owns which workspace, with fake storage and fake windows. No compositor:
-- every effect is a callback in `env`, so the test can say what happened and in
-- which order.
local repo = os.getenv("X_MODE_REPO") or "."
local modesync = dofile(repo .. "/hypr/x-mode/modesync.lua")
local modes = dofile(repo .. "/hypr/x-mode/modes.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
  end
end

local function env(over)
  local e
  e = {
    shared = false,
    state_dir = "/state",
    files = {},
    order = {},
    dirs = {},
    written = {},
    make_dirs = function(d) e.dirs[#e.dirs + 1] = d; return e.dirs_ok ~= false end,
    write = function(path, text) e.files[path] = text end,
    read = function(path) return e.files[path] end,
    workspace_dir = function() return "/omarchy/layouts" end,
    on_enter = function(id) e.order[#e.order + 1] = "enter:" .. id end,
    on_leave = function(id) e.order[#e.order + 1] = "leave:" .. id end,
    apply_all = function(place) e.order[#e.order + 1] = "all:" .. tostring(place) end,
    after_change = function() e.order[#e.order + 1] = "after" end,
    publish = function() e.order[#e.order + 1] = "publish" end,
  }
  for k, v in pairs(over or {}) do e[k] = v end
  return e
end

-- Not shared: the pack's own file is the record, and it is written next to the
-- state directory, not into Omarchy's tree.
local e = env()
local ctl = modesync.new(e)
local function use(c)
  local ev = c.env
  return c:use({
    on_enter = function(id) ev.order[#ev.order + 1] = "enter:" .. id end,
    on_leave = function(id) ev.order[#ev.order + 1] = "leave:" .. id end,
    apply_all = function(place) ev.order[#ev.order + 1] = "all:" .. tostring(place) end,
    after_change = function() ev.order[#ev.order + 1] = "after" end,
    publish = function() ev.order[#ev.order + 1] = "publish" end,
  })
end
use(ctl)
ctl:set(3, "xmode")
ctl:persist()
check("own.written", e.files["/state/workspace-modes.lua"] ~= nil, true)
check("own.mkdir", e.dirs[1], "/state")
check("own.omarchy-file", e.files["/omarchy/layouts/3.lua"], nil)

-- `mkdir -p` is a shell fork: a mode change makes the directory once, not on every
-- write, and a failed creation is not remembered as done.
local e_dirs = env()
local ctl_dirs = modesync.new(e_dirs)
ctl_dirs:persist()
ctl_dirs:persist()
ctl_dirs:persist()
check("dirs.once", #e_dirs.dirs, 1)
local e_fail = env({ dirs_ok = false })
local ctl_fail = modesync.new(e_fail)
ctl_fail:persist()
ctl_fail:persist()
check("dirs.retry-after-failure", #e_fail.dirs, 2)

-- A fresh controller reads that file back, at construction, before any window
-- callback exists: that is what the early consumers of the record see.
local e2 = env({ files = e.files })
local ctl2 = modesync.new(e2)
check("load.restored", ctl2:is_xmode(3), true)
check("load.no-window-effects", #e2.order, 0)
check("load.default", ctl2:default_mode(), nil)

-- Shared: Omarchy's file is the record, the pack writes nothing of its own, and
-- the mode is written where she replays it.
local e3 = env({ shared = true })
local ctl3 = modesync.new(e3)
use(ctl3)
ctl3:set(4, "xmode")
ctl3:persist()
check("shared.no-own-file", e3.files["/state/workspace-modes.lua"], nil)
ctl3:write_workspace(4, "xmode")
check("shared.workspace-file", e3.files["/omarchy/layouts/4.lua"],
  'o.workspace_mode({ workspace = "4", mode = "xmode" })\n')
check("shared.workspace-dir", e3.dirs[1], "/omarchy/layouts")

-- A mode change: record, then the windows, then the publish. Order matters --
-- the dock reads the published mode, and a change on the visible workspace fires
-- no workspace.active to publish it later.
local e4 = env()
local ctl4 = modesync.new(e4)
use(ctl4)
ctl4:apply(5, "xmode")
check("apply.order", table.concat(e4.order, ","), "enter:5,after,publish")
check("apply.recorded", ctl4:is_xmode(5), true)

local e5 = env()
local ctl5 = modesync.new(e5)
use(ctl5)
ctl5:apply(6, "dwindle")
check("leave.order", table.concat(e5.order, ","), "leave:6,after,publish")

-- The default moves every workspace that has no mode of its own, and does not
-- place windows while doing it.
local e6 = env()
local ctl6 = modesync.new(e6)
use(ctl6)
ctl6:apply_default("xmode")
check("default.order", table.concat(e6.order, ","), "all:false,after,publish")
check("default.recorded", ctl6:default_mode(), "xmode")
check("default.is-xmode", ctl6:is_xmode(9), true)

-- An explicit mode beats the default, and is what the pack tags by.
local e7 = env()
local ctl7 = modesync.new(e7)
use(ctl7)
ctl7:apply_default("xmode")
ctl7:apply(7, "dwindle")
check("override.default-xmode", ctl7:is_xmode(8), true)
check("override.explicit", ctl7:is_xmode(7), false)
check("override.mode", ctl7:mode(7), "dwindle")

-- Omarchy's setter is wrapped, not replaced: her call runs, her error stays an
-- error, and the pack's record follows.
local calls = {}
local e8 = env()
local ctl8 = modesync.new(e8)
use(ctl8)
local wrapped = ctl8:wrap_omarchy(function(spec) calls[#calls + 1] = spec.workspace end,
  function() calls[#calls + 1] = "before" end,
  function() calls[#calls + 1] = "after-her" end)
check("wrap.nil-without-original", ctl8:wrap_omarchy(nil), nil)
wrapped({ workspace = "8", mode = "xmode" })
check("wrap.order", table.concat(calls, ","), "before,8,after-her")
check("wrap.recorded", ctl8:is_xmode(8), true)
check("wrap.published", e8.order[#e8.order], "publish")

-- A default in the same call goes down the default path.
calls = {}
wrapped({ default = "xmode" })
check("wrap.default", ctl8:default_mode(), "xmode")
check("wrap.default-effects", e8.order[#e8.order - 2], "all:false")

-- Her error is not swallowed, and the pack does not record a mode she refused.
local e9 = env()
local ctl9 = modesync.new(e9)
use(ctl9)
local failing = ctl9:wrap_omarchy(function() error("nope") end, function() end, function() end)
local ok = pcall(failing, { workspace = "9", mode = "xmode" })
check("wrap.error-propagates", ok, false)
check("wrap.no-record-after-error", ctl9:is_xmode(9), false)

-- A spec that is not a table, or has no workspace, changes nothing.
local e10 = env()
local ctl10 = modesync.new(e10)
local w10 = ctl10:wrap_omarchy(function() end, function() end, function() end)
w10("nonsense")
w10({ mode = "xmode" })
check("wrap.ignores-junk", #e10.order, 0)

if failures > 0 then
  os.exit(1)
end
print("modesync ok")
