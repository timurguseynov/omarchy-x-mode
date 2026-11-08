-- Reconciliation: the controller's memory and the compositor's table are two
-- separate things, and the whole point is that losing the table does not go
-- unnoticed. The fake keeps both, so the test can delete from the live table only
-- and watch what the next tick does about it.
local repo = os.getenv("X_MODE_REPO") or "."
local keys = dofile(repo .. "/hypr/x-mode/keys.lua")
local sm = dofile(repo .. "/hypr/x-mode/supermap.lua")

local failures = 0
local last_meta = ""

local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s (meta: %s)", name, tostring(got), tostring(want),
      last_meta ~= "" and last_meta or "none"))
  end
end

-- The free keys the plan will take: a small table, so the test's numbers are
-- readable. Everything a real desktop binds is absent here.
local TABLE_TEXT = table.concat({
  "bind", "\tmodmask: 64", "\tsubmap: ", "\tkey: L", "\tkeycode: 0",
  "\tdescription: Lock the screen", "\tdispatcher: exec", "",
}, "\n")

-- An Omarchy bind the pack may take over. It lives in the table as an entry like
-- any other, so installing the wrap really removes it -- that is the case the
-- recovery has to survive.
local ORIGINAL_Z = table.concat({
  "bind", "\tmodmask: 64", "\tsubmap: ", "\tkey: Z", "\tkeycode: 0",
  "\tdescription: Undo", "\tdispatcher: exec", "\targ: hyprctl notify 1 1 0 Undo", "",
}, "\n")

local function fake()
  local e
  e = {
    live = {},          -- our binds, as the compositor holds them: { id=, keys= }
    foreign = {},       -- binds that are not ours, and must never be touched
    timers = {},        -- oneshot timers to drain
    released = {},      -- key strings our handles released
    written = {},
    binds = {},
    gen = 0,
    token = "t1",
    flag = true,
  }
  function e.bind(keys_str, fn, opts)
    e.binds[#e.binds + 1] = keys_str
    local desc = opts and opts.description or ""
    -- The chord is not always the last word: a wrap's description carries the
    -- original action after the id ("x-mode-super-steal Z Undo").
    local steal = desc:match("^x%-mode%-super%-steal%s+(%S+)")
    local id
    if steal ~= nil then
      id = steal
    else
      local shift = desc:find("SHIFT", 1, true) ~= nil
      local key = desc:match("%s(%S+)$") or ""
      id = (shift and "SHIFT+" or "") .. key
    end
    e.live[#e.live + 1] = { id = id, keys = keys_str, desc = desc, steal = steal ~= nil, fn = fn }
    return true, { keys = keys_str }
  end
  function e.restore(keys_str, orig)
    e.restored = e.restored or {}
    e.restored[#e.restored + 1] = { keys = keys_str, orig = orig }
    -- A restore is a real bind again: the action is back in the table, which is what
    -- makes the "restored and then planned over" case observable.
    local key = keys_str:match("^SUPER%s*%+%s*(.+)$") or keys_str
    e.foreign[#e.foreign + 1] = {
      keys = keys_str,
      text = table.concat({
        "bind", "\tmodmask: 64", "\tsubmap: ", "\tkey: " .. key, "\tkeycode: 0",
        "\tdescription: " .. tostring(orig and orig.description or "restored"),
        "\tdispatcher: exec", "",
      }, "\n"),
    }
  end
  function e.release(handle)
    e.released[#e.released + 1] = handle and handle.keys or "?"
    for i = #e.live, 1, -1 do
      if e.live[i].keys == (handle and handle.keys) then
        table.remove(e.live, i)
        break
      end
    end
  end
  function e.unbind(key)
    -- Installing a wrap unbinds the original, so the table no longer holds it: a
    -- fake that keeps it would hide exactly the case this has to survive.
    for i = #e.live, 1, -1 do
      if e.live[i].keys == key then table.remove(e.live, i) end
    end
    for i = #e.foreign, 1, -1 do
      if e.foreign[i].keys == key then table.remove(e.foreign, i) end
    end
  end
  function e.replay(orig)
    e.replayed = e.replayed or {}
    e.replayed[#e.replayed + 1] = orig
  end
  function e.active_window() return nil end
  function e.window_class() return "" end
  function e.key_stolen() return false end
  function e.send_ctrl() end
  function e.flag_any() return e.flag end
  function e.flag_for() return true end
  function e.needed_ids() return {} end
  function e.exec_for() return nil end
  function e.exec_ids() return {} end
  function e.ensure_replay() end
  function e.write(name, text)
    e.written[name] = text
    if name == "super-ctrl.json" then last_meta = text end
  end
  function e.remove(name) e.removed = name end
  function e.remove_path() end
  function e.now() return 0 end
  e.binds_path = "/state/binds.txt"
  function e.exec() end
  function e.timer(fn, opts)
    if opts and opts.type == "repeat" then
      -- The interval timer is not part of a tick: the test calls verify() itself.
      return { set_enabled = function() end, is_repeat = true }
    end
    e.timers[#e.timers + 1] = fn
    return { set_enabled = function() end }
  end
  function e.read()
    -- The live table as the compositor would print it, plus the stamp of the
    -- generation being asked for: the fake always answers "freshly".
    local out = { TABLE_TEXT }
    for _, b in ipairs(e.live) do
      local shift = b.id:sub(1, 6) == "SHIFT+"
      local key = shift and b.id:sub(7) or b.id
      out[#out + 1] = table.concat({
        "bind", "\tmodmask: " .. (shift and 65 or 64), "\tsubmap: ",
        "\tkey: " .. key, "\tkeycode: 0", "\tdescription: " .. b.desc,
        "\tdispatcher: __lua", "",
      }, "\n")
    end
    for _, f in ipairs(e.foreign) do
      out[#out + 1] = f.text
    end
    out[#out + 1] = "@gen " .. e.token .. " " .. tostring(e.ctl and e.ctl.gen or 0) .. "\n"
    return table.concat(out, "\n")
  end
  return e
end

-- Run exactly one queued timer: the reconciliation's tick and the rebuild it starts
-- are separate steps, and the case worth testing lives between them.
local function step(e)
  local fn = table.remove(e.timers, 1)
  if fn ~= nil then fn() end
end

local function drain(e)
  for _ = 1, 200 do
    local fn = table.remove(e.timers, 1)
    if fn == nil then
      return
    end
    fn()
  end
end

-- 1. Install the map: the plan binds every free key, and the live table follows.
local e = fake()
e.foreign = {
  { keys = "SUPER + K", text = table.concat({
    "bind", "\tmodmask: 64", "\tsubmap: ", "\tkey: K", "\tkeycode: 0",
    "\tdescription: Omarchy keybindings", "\tdispatcher: exec", "",
  }, "\n") },
}
local ctl = keys.new(e)
e.ctl = ctl
ctl:apply()
drain(e)
check("install.binds", #e.live > 0, true)
check("install.meta-pending", (e.written["super-ctrl.json"] or ""):find('"state":"pending"', 1, true) ~= nil, true)

-- 2. Lose part of the map from the compositor only: the controller still holds
-- every handle, which is exactly the state that used to look healthy.
local lost = table.remove(e.live, 1)
check("lost.removed-one", #e.live >= 0, true)

-- 3. One reconciliation tick: it must notice, say so, and rebuild on its own.
ctl:verify()
drain(e)
check("verify.degraded", (e.written["super-ctrl.json"] or ""):find('"state":"degraded"', 1, true) ~= nil, true)
check("verify.rebuilt", #e.live, #e.binds - #e.released + #e.live - #e.live + #e.live > 0 and #e.live or 0)

-- The rebuilt table holds the lost chord again, exactly once.
local count = {}
for _, b in ipairs(e.live) do count[b.id] = (count[b.id] or 0) + 1 end
check("verify.lost-chord-back", count[lost.id], 1)
local duplicates = 0
for _, n in pairs(count) do
  if n > 1 then duplicates = duplicates + 1 end
end
check("verify.no-duplicates", duplicates, 0)

-- 4. A tick with nothing wrong says verified.
ctl:verify()
drain(e)
check("verify.verified", (e.written["super-ctrl.json"] or ""):find('"state":"verified"', 1, true) ~= nil, true)

-- 5. A duplicate of one of our chords is a defect even though the count only grew:
-- the set comparison has to see it.
local dup = { id = e.live[1].id, keys = "SUPER + duplicate", desc = e.live[1].desc }
e.live[#e.live + 1] = dup
ctl:verify()
drain(e)
check("verify.duplicate-degraded", (e.written["super-ctrl.json"] or ""):find('"state":"degraded"', 1, true) ~= nil, true)

-- 6. A foreign bind is never released and never counted as ours: the reconciliation
-- only looks at descriptions it wrote.
local foreign_released = false
for _, key in ipairs(e.released) do
  if key == "SUPER + K" then foreign_released = true end
end
check("verify.foreign-untouched", foreign_released, false)
-- The observation survives the rebuild that follows a failed check: a bare state
-- with `observed: null` would be the same "no idea" the old file always showed.
local final_meta = e.written["super-ctrl.json"] or ""
check("verify.observed-kept", final_meta:find('"observed":null') == nil, true)
check("verify.observed-number", final_meta:match('"observed":(%d+)') ~= nil, true)

-- A wrap that disappears is rebuilt, not just reported: the memory entry has to be
-- forgotten first, because a handle the compositor no longer has cannot be repaired.
local e7 = fake()
e7.foreign = { { keys = "SUPER + Z", text = ORIGINAL_Z } }
local c7 = keys.new(e7)
e7.ctl = c7
e7.needed_ids = function() return { Z = true } end
c7:apply()
drain(e7)
local wrapped = false
for _, b in ipairs(e7.live) do
  if b.steal and b.id == "Z" then wrapped = true end
end
check("wrap.installed", wrapped, true)
local original_left = 0
for _, f in ipairs(e7.foreign) do
  if f.keys == "SUPER + Z" then original_left = original_left + 1 end
end
check("wrap.original-unbound", original_left, 0)
c7:verify()
drain(e7)
check("wrap.verified-first", (e7.written["super-ctrl.json"] or ""):find('"state":"verified"', 1, true) ~= nil, true)

for i = #e7.live, 1, -1 do
  if e7.live[i].steal and e7.live[i].id == "Z" then table.remove(e7.live, i) end
end
c7:verify()
drain(e7)
local rebuilt = false
for _, b in ipairs(e7.live) do
  if b.steal and b.id == "Z" then rebuilt = true end
end
check("wrap.rebuilt", rebuilt, true)

-- The rebuilt wrap still replays Omarchy's action for an app that does not steal
-- the key: the original was unbound from the table when the wrap was installed, so
-- it can only come from the intent memory kept.
check("wrap.intent-kept", c7.wrap_intent.Z ~= nil, true)
local on_z = 0
for _, b in ipairs(e7.live) do
  if b.id == "Z" then on_z = on_z + 1 end
end
check("wrap.one-handler", on_z, 1)
check("wrap.intent-original", (c7.wrap_intent.Z.originals or {})[1] ~= nil, true)

-- Pressing the rebound chord with an app that does not steal it replays that
-- original action (the fake records replays).
local z_handler = nil
for _, b in ipairs(e7.live) do
  if b.steal and b.id == "Z" then z_handler = b.fn end
end
check("wrap.handler-bound", z_handler ~= nil, true)
if z_handler ~= nil then
  e7.replayed = {}
  z_handler()
  check("wrap.replays-original", #e7.replayed > 0, true)
end

-- Giving the chord back after the wrap was lost still restores Omarchy's action:
-- the handle is gone, so the originals can only come from the intent. Without this
-- the key ends up with no handler at all.
local e9 = fake()
e9.foreign = { { keys = "SUPER + Z", text = ORIGINAL_Z } }
local c9 = keys.new(e9)
e9.ctl = c9
local need_z = true
e9.needed_ids = function()
  if need_z then return { Z = true } end
  return {}
end
c9:apply()
drain(e9)
-- The wrap disappears from the compositor, and the reconciliation forgets its handle.
for i = #e9.live, 1, -1 do
  if e9.live[i].steal and e9.live[i].id == "Z" then table.remove(e9.live, i) end
end
-- One tick of the check: it sees the wrap gone, forgets the handle and starts the
-- rebuild. Stopped before the rebuild's own snapshot answers, which is the moment
-- the app may stop needing the key.
c9:verify()
step(e9)
check("release.handle-forgotten", c9.wraps.Z == nil, true)
check("release.intent-kept-after-loss", c9.wrap_intent.Z ~= nil, true)
need_z = false
e9.restored = {}
c9:apply()          -- replaces the pending rebuild, plans with the old snapshot
drain(e9)
local restored_z = false
for _, r in ipairs(e9.restored or {}) do
  if r.keys == "SUPER + Z" then restored_z = true end
end
check("release.original-restored", restored_z, true)
check("release.intent-dropped", c9.wrap_intent.Z == nil, true)

-- And nothing was planned over it: one handler on the chord, the restored original,
-- not a generated Ctrl bind next to it.
local handlers_on_z = 0
local generated_on_z = 0
-- The restored original is a table entry again (the fake keeps those in `foreign`),
-- and our own binds live in `live`.
for _, f in ipairs(e9.foreign) do
  if f.keys == "SUPER + Z" then handlers_on_z = handlers_on_z + 1 end
end
for _, b in ipairs(e9.live) do
  if b.id == "Z" then
    handlers_on_z = handlers_on_z + 1
    if not b.steal then generated_on_z = generated_on_z + 1 end
  end
end
check("release.one-handler", handlers_on_z, 1)
check("release.no-ctrl-bind-over-original", generated_on_z, 0)

-- A second install with nothing changed must keep the healthy wrap in the wanted set:
-- otherwise the reconciliation calls its own wrap a leftover and rebuilds forever.
local e8 = fake()
e8.foreign = { { keys = "SUPER + Z", text = ORIGINAL_Z } }
local c8 = keys.new(e8)
e8.ctl = c8
e8.needed_ids = function() return { Z = true } end
c8:apply()
drain(e8)
local live_after_first = #e8.live
c8:apply()
drain(e8)
-- A plan drops and rebinds its own map, so the calls repeat; what must not change is
-- the table the compositor ends up holding.
check("rerun.no-duplicate-binds", #e8.live, live_after_first)
check("rerun.wrap-still-wanted", #c8.desired_steals, 1)
c8:verify()
drain(e8)
check("rerun.verified", (e8.written["super-ctrl.json"] or ""):find('"state":"verified"', 1, true) ~= nil, true)
check("rerun.no-rebuild", #e8.live, live_after_first)

-- 7. An install that fails for one chord does not shrink the requirements: the chord
-- stays wanted, so the next check reports it missing instead of calling the map
-- healthy.
local e4 = fake()
local c4 = keys.new(e4)
e4.ctl = c4
local fail_once = { R = true }
local real_bind = e4.bind
function e4.bind(keys_str, fn, opts)
  local desc = opts and opts.description or ""
  if fail_once.R and desc:match("x%-mode%-super%-ctrl R$") then
    fail_once.R = false
    return false, nil
  end
  return real_bind(keys_str, fn, opts)
end
c4:apply()
drain(e4)
local has_r = false
for _, id in ipairs(c4.desired) do
  if id == "R" then has_r = true end
end
check("failed-bind.still-wanted", has_r, true)
c4:verify()
drain(e4)
check("failed-bind.reported", (e4.written["super-ctrl.json"] or ""):find('"state":"degraded"', 1, true) ~= nil, true)

-- 8. After the fast attempts are used up the reconciliation slows down instead of
-- giving up: the next tick inside the minute does nothing.
local e5 = fake()
local c5 = keys.new(e5)
e5.ctl = c5
e5.read = function() return "@gen " .. e5.token .. " " .. tostring(c5.gen) .. "\n" end
c5.desired = { "R" }
c5.desired_steals = {}
c5:verify()
drain(e5)
for _ = 1, 5 do
  c5.pause_until = nil
  c5:verify()
  drain(e5)
end
check("slow.paused", c5.pause_until ~= nil, true)
local timers_before = #e5.timers
c5:verify()
check("slow.tick-is-quiet-while-paused", #e5.timers, timers_before)

-- A verification tick must never strand an install: while a plan is waiting for its
-- own snapshot, verify does nothing at all. Otherwise the tick would move the
-- generation, the plan's read would be ignored, and the map would never land.
local e2 = fake()
local c2 = keys.new(e2)
e2.ctl = c2
c2:apply()
local queued_before = #e2.timers
c2:verify()
check("guard.verify-is-a-no-op-mid-apply", #e2.timers, queued_before)
drain(e2)
check("guard.plan-landed", #e2.live > 0, true)

-- An install that replaces a running check must clear the check's flag: otherwise
-- `verifying` stays up and the reconciliation never runs again.
local e3 = fake()
local c3 = keys.new(e3)
e3.ctl = c3
c3:apply()
drain(e3)
c3.desired = c3.desired   -- keep the map
c3:verify()
check("race.verifying-set", c3.verifying, true)
c3:apply()                -- replaces the check mid-flight
check("race.verifying-cleared", c3.verifying, false)
drain(e3)
check("race.applying-cleared", c3.applying, false)
c3:verify()               -- must be able to run again
check("race.verify-runs-again", c3.verifying, true)
drain(e3)

-- A wrap that vanished is a missing part of the map, and the state has to say so:
-- the generated chords can all be there while a stolen key silently stopped working.
local e6 = fake()
e6.foreign = { { keys = "SUPER + Z", text = ORIGINAL_Z } }
local c6 = keys.new(e6)
e6.ctl = c6
e6.needed_ids = function() return { Z = true } end
c6:apply()
drain(e6)
local wraps_wanted = #c6.desired_steals
check("wrap.wanted", wraps_wanted, 1)
-- Drop the wrap from the live table only.
for i = #e6.live, 1, -1 do
  if e6.live[i].id == "Z" then table.remove(e6.live, i) end
end
c6:verify()
drain(e6)
check("wrap.lost-degraded", (e6.written["super-ctrl.json"] or ""):find('"state":"degraded"', 1, true) ~= nil, true)

if failures > 0 then
  os.exit(1)
end
print("keys reconcile ok")
