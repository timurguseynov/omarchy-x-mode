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

local function env(over)
  local e
  e = {
    bound = {},
    released = 0,
    restored = {},
    replayed = {},
    written = {},
    removed = {},
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
    read = function() return RAW end,
    exec = function() end,
    now = function() return 0 end,
    binds_path = "/state/binds.txt",
    flag_any = function(name) return e.flag[name] ~= false end,
    flag_for = function(cls, name)
      if e.per_class and e.per_class[cls] ~= nil then
        return e.per_class[cls]
      end
      return e.flag[name] ~= false
    end,
    write = function(name, text) e.written[name] = text end,
    remove = function(name) e.removed[name] = true end,
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

-- A wrap replays the original action for an app that does not steal the key.
local e7 = env({
  needed_ids = function() return { Z = true } end,
  exec_ids = function() return {} end,
})
local ctl7 = keys.new(e7)
ctl7:plan(RAW, 0)
local wrap = nil
for _, b in ipairs(e7.bound) do
  if b.keys == "SUPER + Z" then wrap = b end
end
check("wrap.installed", wrap ~= nil, true)
wrap.fn()
check("wrap.replays-original", e7.replayed[1], "sendshortcut")

-- Same wrap, but the app steals Z: the press is sent as Ctrl instead.
e7.key_stolen = function() return true end
e7.sent = {}
wrap.fn()
check("wrap.stolen-sends-ctrl", e7.sent[1], "Z")

-- The key is no longer needed: the wrap is unhooked and the original restored.
e7.needed_ids = function() return {} end
ctl7:plan(RAW, 0)
check("wrap.dropped", e7.restored[1], "SUPER + Z:sendshortcut")

if failures > 0 then
  os.exit(1)
end
print("keys ok")
