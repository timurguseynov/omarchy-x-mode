-- The Super-as-Ctrl ownership model, with a fake compositor: what gets bound,
-- what gets dropped when the option goes off, what a late plan does, and where a
-- key press is routed. No Hyprland: every side effect is a function in `env`.
local repo = os.getenv("X_MODE_REPO") or "."
local keys = dofile(repo .. "/hypr/x-mode/keys.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
  end
end

-- A bind table in the shape `hyprctl binds` prints: one block per bind.
local RAW = table.concat({
  "bind",
  "\tmodmask: 64",
  "\tsubmap: ",
  "\tkey: Z",
  "\tkeycode: 0",
  "\tdescription: undo",
  "\tdispatcher: sendshortcut",
  "\targ: CTRL SHIFT, Z,",
  "",
  "bind",
  "\tmodmask: 64",
  "\tsubmap: ",
  "\tkey: X",
  "\tkeycode: 0",
  "\tdescription: cut",
  "\tdispatcher: sendshortcut",
  "\targ: CTRL, X,",
  "",
}, "\n")

-- A snapshot is only an answer when it carries the generation that asked for it.
local RAW_STAMPED = RAW .. "\n@gen t1 1\n"

local function env(over)
  local e
  e = {
    bound = {},
    released = 0,
    restored = {},
    replayed = {},
    written = {},
    removed = {},
    removed_paths = {},
    sent = {},
    timers = {},
    flag = { ctrl_as_super = true },
    steal_own = { Q = true, TAB = true, F = true, W = true },
    exec_ids = function() return {} end,
    exec_for = function() return nil end,
    needed_ids = function() return {} end,
    ensure_replay = function() end,
    active_window = function() return { address = "w1", class = "foot" } end,
    window_class = function() return "foot" end,
    key_stolen = function() return false end,
    send_ctrl = function(key, shift) e.sent[#e.sent + 1] = key end,
    replay = function(orig) e.replayed[#e.replayed + 1] = orig.dispatcher end,
    restore = function(k, orig) e.restored[#e.restored + 1] = k .. ":" .. tostring(orig.dispatcher) end,
    read = function() return RAW_STAMPED end,
    exec = function() end,
    now = function() return 0 end,
    binds_path = "/state/binds.txt",
    token = "t1",
    flag_any = function(name) return e.flag[name] ~= false end,
    flag_for = function(cls, name)
      if e.per_class and e.per_class[cls] ~= nil then
        return e.per_class[cls]
      end
      return e.flag[name] ~= false
    end,
    write = function(name, text) e.written[name] = text end,
    remove = function(name) e.removed[name] = true end,
    remove_path = function(path) e.removed_paths[#e.removed_paths + 1] = path end,
    timer = function(fn, opts) e.timers[#e.timers + 1] = fn; e.timer_opts = opts end,
    unbind = function(k) e.unbound = (e.unbound or 0) + 1 end,
    release = function() e.released = e.released + 1 end,
    bind = function(k, fn, opts)
      e.bound[#e.bound + 1] = { keys = k, fn = fn, opts = opts }
      return true, { keys = k }
    end,
  }
  for k, v in pairs(over or {}) do e[k] = v end
  return e
end

-- apply() bumps the generation, shells out for the table, and asks for a timer.
local e = env()
local ctl = keys.new(e)
local gen = ctl:apply()
check("apply.generation", gen, 1)
check("apply.timer", #e.timers, 1)
check("apply.timer-timeout", e.timer_opts.timeout, 200)
check("apply.timer-oneshot", e.timer_opts.type, "oneshot")
check("apply.nothing-bound-before-read", #e.bound, 0)

-- The timer fires with the table: the plan installs free keys, not wraps.
e.timers[1]()
check("plan.binds", #e.bound > 0, true)
check("plan.every-bind-repeats", (function()
  for _, b in ipairs(e.bound) do
    if b.opts.repeating ~= true then return false end
  end
  return true
end)(), true)
check("plan.meta-writes-planned", e.written["super-ctrl.json"] ~= nil, true)
check("plan.occupied-written", e.written["occupied.json"] ~= nil, true)

-- A key press on an installed bind goes to the app as Ctrl when the flag is on.
e.bound[1].fn()
check("route.sent-ctrl", #e.sent, 1)

-- The flag is per class, not "on somewhere": a window of an app with it off
-- keeps its plain Super+key even while another app has the option on.
e.per_class = { foot = false, kitty = true }
e.sent = {}
e.bound[1].fn()
check("route.per-class-off", #e.sent, 0)
e.window_class = function() return "kitty" end
e.bound[1].fn()
check("route.per-class-on", #e.sent, 1)
e.window_class = function() return "foot" end
e.per_class = nil

-- Option off: the installed map goes, and the file says so.
e.flag.ctrl_as_super = false
e.sent = {}
ctl:plan(RAW, ctl.gen)
check("off.released-all", e.released, #e.bound)
check("off.meta-zero", e.written["super-ctrl.json"], '{"planned":0,"bound":0,"keys":0}\n')
check("off.no-new-sends", #e.sent, 0)

-- A late plan from an older generation is dropped without binding anything.
local e2 = env()
local ctl2 = keys.new(e2)
ctl2:apply()
ctl2:apply()
local stale = ctl2.gen - 1
e2.bound = {}
ctl2:plan(RAW, stale)
check("stale.no-binds", #e2.bound, 0)

-- A torn table is not an answer: nothing planned, nothing dropped.
local e3 = env()
local ctl3 = keys.new(e3)
ctl3:plan("bind\n\tkey: Z\n\tdispatcher: sendshortcut", 0)
check("torn.no-binds", #e3.bound, 0)
check("torn.no-drop", e3.released, 0)

-- Nothing planned while the option is on: the installed map stays.
local e4 = env()
local ctl4 = keys.new(e4)
ctl4:plan("", 0)
check("empty.no-binds", #e4.bound, 0)
check("empty.no-meta-write", e4.written["super-ctrl.json"], nil)

-- Self-heal only when the map is empty, the option is on, and the gap passed.
local e5 = env()
local ctl5 = keys.new(e5)
check("heal.fires", ctl5:self_heal(), true)
check("heal.rate-limited", ctl5:self_heal(), false)
e5.flag.ctrl_as_super = false
local e6 = env({ flag = { ctrl_as_super = false } })
check("heal.off-does-nothing", keys.new(e6):self_heal(), false)

-- A snapshot is only an answer for the attempt that asked for it: the exec stamps
-- the generation it was taken for, so a file written by an older, slower attempt
-- cannot be planned under a newer generation. That is what lets a stuck read be
-- replaced instead of serialised.
local clock = 0
local e7 = env({ now = function() return clock end, read = function() return nil end })
local ctl7 = keys.new(e7)
local execs = 0
local last_exec = ""
e7.exec = function(cmd) execs = execs + 1; last_exec = cmd end
ctl7:apply()
check("fresh.exec-once", execs, 1)
check("fresh.exec-stamps-generation", last_exec:find("@gen t1 1", 1, true) ~= nil, true)

-- The file that lands carries an older generation: not an answer, so no binds.
e7.read = function() return RAW .. "\n@gen t1 0\n" end
e7.timers[1]()
check("fresh.stale-snapshot-ignored", #e7.bound, 0)

-- A torn file has no stamp at all: also not an answer.
e7.read = function() return "bind\n\tmodmask: 64" end
e7.timers[2]()
check("fresh.torn-ignored", #e7.bound, 0)

-- The stamp that matches installs the plan.
e7.read = function() return RAW .. "\n@gen t1 1\n" end
e7.timers[3]()
check("fresh.matching-snapshot-planned", #e7.bound > 0, true)
-- Two overlapping attempts must not share a scratch path: an older `hyprctl`
-- rewriting a newer attempt's file would get stamped with the newer generation.
local first = last_exec
ctl7:apply()
check("fresh.per-attempt-scratch", last_exec ~= first, true)
check("fresh.second-stamp", last_exec:find("@gen t1 2", 1, true) ~= nil, true)
local scratch_first = first:match("binds%.txt%.[%w%.]+%.raw")
local scratch_second = last_exec:match("binds%.txt%.[%w%.]+%.raw")
check("fresh.distinct-raw", scratch_first ~= scratch_second, true)
-- The scratch cleanup has to hand the adapter the same absolute path the command
-- wrote: a name would be joined with the state directory a second time and the
-- file would survive every attempt.
check("fresh.cleanup-path-is-absolute", e7.removed_paths[1], "/state/binds.txt.t1.1.raw")
check("fresh.cleanup-matches-command", first:find("/state/binds%.txt%.t1%.1%.raw", 1) ~= nil or first:find("/state/binds.txt.t1.1.raw", 1, true) ~= nil, true)

-- A reload starts a new controller whose generation begins again at one. The
-- snapshot the previous instance left behind carries that same generation, so the
-- token has to be checked too -- otherwise a fresh load plans the old table before
-- its own `hyprctl` has said anything.
local shared = { file = RAW .. "\n@gen t1 1\n" }
local e10 = env({ token = "t2", read = function() return shared.file end })
local ctl10 = keys.new(e10)
ctl10:apply()
e10.timers[1]()
check("reload.foreign-token-ignored", #e10.bound, 0)
shared.file = RAW .. "\n@gen t2 1\n"
e10.timers[2]()
check("reload.own-token-planned", #e10.bound > 0, true)

-- A stuck read is still replaceable: the recovery path the nest scenario guards.
local e8 = env({ read = function() return nil end })
local ctl8 = keys.new(e8)
local execs8 = 0
local clock8 = 0
e8.exec = function() execs8 = execs8 + 1 end
e8.now = function() return clock8 end
ctl8:apply()
clock8 = 6
check("recover.heal-fires", ctl8:self_heal(), true)
check("recover.second-exec", execs8, 2)

-- A wrap replays the original action for an app that does not steal the key.
local e9 = env({
  needed_ids = function() return { Z = true } end,
  exec_ids = function() return {} end,
})
local ctl9 = keys.new(e9)
ctl9:plan(RAW, 0)
local wrap = nil
for _, b in ipairs(e9.bound) do
  if b.keys == "SUPER + Z" then wrap = b end
end
check("wrap.installed", wrap ~= nil, true)
wrap.fn()
check("wrap.replays-original", e9.replayed[1], "sendshortcut")

-- Same wrap, but the app steals Z: the press is sent as Ctrl instead.
e9.key_stolen = function() return true end
e9.sent = {}
wrap.fn()
check("wrap.stolen-sends-ctrl", e9.sent[1], "Z")

-- The key is no longer needed: the wrap is unhooked and the original restored.
e9.needed_ids = function() return {} end
ctl9:plan(RAW, 0)
check("wrap.dropped", e9.restored[1], "SUPER + Z:sendshortcut")

if failures > 0 then
  os.exit(1)
end
print("keys ok")
