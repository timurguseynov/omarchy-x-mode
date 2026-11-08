-- Super as Ctrl: which keys the pack takes over for the focused app, which
-- original Omarchy action each of them replays when the app does not want it, and
-- how a plan that arrives late is thrown away instead of installed over a newer
-- one. The compositor is reached only through `env`, so the whole ownership model
-- is testable in plain lua with a fake binder (tests/unit/keys_test.lua).
--
-- Two maps live here and they are not the same thing:
--   free     the Super+key combinations nothing else binds, sent to the app as
--            Ctrl+key. Planned from the compositor's own bind table.
--   wraps    keys Omarchy binds and the pack has taken over, so the app can get
--            Ctrl+key while every other app still gets Omarchy's action back.
-- Both are torn down and rebuilt by one generation counter: a read that lands
-- late must not install a table that a newer request has already replaced.
local M = {}

local sm = dofile(((debug.getinfo(1, "S").source or ""):match("^@(.*/)") or "./") .. "supermap.lua")

-- env, supplied by x-mode.lua (everything that touches the compositor or disk):
--   bind(keys, fn, opts) -> ok, handle    unbind(keys)
--   release(handle)                       restore(keys, orig)   replay(orig)
--   active_window() -> w                  window_class(w) -> cls
--   key_stolen(cls, key, shift) -> bool   send_ctrl(key, shift, w)
--   flag_any(name) -> bool                flag_for(cls, name) -> bool
--   needed_ids() -> set of ids to wrap
--   exec_for(id) -> command|nil           exec_ids() -> table     ensure_replay()
--   write(name, text)                     remove(name)         (a state-dir name)
--   remove_path(path)                     (an absolute path, for the scratch files)
--   read(path) -> text|nil                exec(cmd)             timer(fn, opts)
--   now() -> seconds                      binds_path            steal_own
--   token                                 unique per controller instance
function M.new(env)
  -- The generation alone is not unique: a reload starts a new controller whose
  -- counter begins at one again, and the snapshot the previous load left behind
  -- carries `gen 1` too. The token names this instance; a snapshot has to match
  -- both parts to be an answer.
  local self = {
    env = env, gen = 0, binds = {}, wraps = {}, retry_at = 0, token = env.token,
    -- The map the last plan wanted, as chord ids ("R", "SHIFT+T"), and what the
    -- compositor was last observed to hold. `verify_failures` bounds the replans so
    -- a map that cannot converge does not rebuild itself forever.
    desired = {}, wrap_intent = {}, verify_timer = nil, verifying = false, applying = false, verify_failures = 0,
    pause_until = nil,
  }

  function self:drop()
    for _, handle in ipairs(self.binds) do
      self.env.release(handle)
    end
    self.binds = {}
  end

  -- What the pack knows, next to the files the panel and the tests read.
  --
  -- `planned` and `installed` are the attempt: what the plan wanted and how many
  -- `hl.bind` calls came back with a handle. `observed` is what the compositor's
  -- table was seen to hold, and it is `null` until something looks -- so a plan
  -- alone can never claim the map is there. `state` says which of those the numbers
  -- are: "pending" (installed, not yet observed), "unknown" (the read never landed),
  -- "off" (the option is off and the map was dropped), and -- once a reconciliation
  -- pass exists -- "verified" and "degraded".
  --
  -- Written on every pass, including the ones that bind nothing: a file that only a
  -- successful plan rewrites keeps the last good numbers through a map that has been
  -- dropped, which is how a dead Super as Ctrl looked healthy.
  function self:write_meta(planned, installed, state, observed)
    self.env.write("super-ctrl.json", string.format(
      '{"planned":%d,"bound":%d,"keys":%d,"observed":%s,"state":"%s"}\n',
      planned, installed, #self.binds, tostring(observed or "null"), tostring(state or "pending")))
  end

  function self:write_occupied(raw)
    -- Built before the file is opened, and only written when it built: opening
    -- with "w" truncates first, so a build that died left an empty occupied.json
    -- and the panel's list of keys to replace simply vanished -- a bug that reads
    -- as "the panel lost its rows", not as a write that failed.
    local ok, json = pcall(function()
      return sm.occupied_json(sm.stealable(raw, self.env.steal_own, self.env.exec_ids()))
    end)
    if not ok or type(json) ~= "string" then
      -- Say why, next to the file the panel reads: a silent failure here is a
      -- panel that quietly shows nothing.
      self.env.write("occupied.error", tostring(json) .. "\n")
      return
    end
    self.env.write("occupied.json", json .. "\n")
    self.env.remove("occupied.error")
  end

  -- Give up the chord: release the handle if it is still live, and restore the
  -- original action either way. The intent carries the originals as well, because a
  -- wrap whose handle the compositor lost has no handle left to read them from --
  -- and giving the chord back without its action leaves the desktop without the
  -- Omarchy command that used to be on it.
  function self:drop_wrap(id)
    local wrap = self.wraps[id]
    local intent = self.wrap_intent[id]
    if wrap ~= nil then
      self.env.release(wrap.handle)
    end
    local keys = (wrap and wrap.keys) or (intent and intent.keys)
    local originals = (wrap and wrap.originals) or (intent and intent.originals)
    if keys ~= nil and originals ~= nil then
      for _, orig in ipairs(originals) do
        self.env.restore(keys, orig)
      end
    end
    if keys ~= nil and originals ~= nil and self.restored_chords ~= nil then
      -- Remembered for this pass only: the plan below is built from the snapshot
      -- taken *before* this restore, so that snapshot still shows the chord as free
      -- and would put a plain Ctrl bind on top of the action just given back.
      self.restored_chords[id] = true
    end
    self.wraps[id] = nil
    self.wrap_intent[id] = nil
  end

  -- Keys Omarchy binds that the pack has taken over, so an app that wants Ctrl
  -- gets it while every other app keeps Omarchy's action.
  -- The intent of a wrap, kept apart from its handle: the chord it takes and the
  -- action it replays for every other app. Installing a wrap unbinds Omarchy's own
  -- bind from the compositor, so a fresh snapshot cannot say what that action was --
  -- dropping the intent together with the handle would turn the chord into a plain
  -- Ctrl bind for every app but the one that asked for it.
  local function install_wrap(self, id)
    local intent = self.wrap_intent[id]
    if intent == nil then
      return false
    end
    self.env.unbind(intent.keys)
    local code = sm.key_code(intent.key)
    if code ~= nil then
      local ck = intent.shift and ("SUPER + SHIFT + code:" .. tostring(code)) or ("SUPER + code:" .. tostring(code))
      self.env.unbind(ck)
    end
    local key, shift = intent.key, intent.shift
    local originals = intent.originals
    local ok, handle = self.env.bind(intent.keys, function()
      local w = self.env.active_window()
      if w ~= nil and self.env.key_stolen(self.env.window_class(w), key, shift) then
        self.env.send_ctrl(key, shift, w)
        return
      end
      for _, orig in ipairs(originals) do
        self.env.replay(orig)
      end
    end, { description = sm.steal_desc(id, intent.description) })
    if ok and handle then
      self.wraps[id] = { keys = intent.keys, originals = originals, handle = handle }
      return true
    end
    return false
  end

  function self:apply_wraps(raw)
    local needed = self.env.needed_ids()
    self.desired_steals = {}
    self.restored_chords = {}
    for id in pairs(self.wraps) do
      if not needed[id] then
        self:drop_wrap(id)
      end
    end
    for id in pairs(self.wrap_intent) do
      if not needed[id] then
        self:drop_wrap(id)
      end
    end
    if next(needed) == nil then
      return
    end
    local by_id = {}
    for _, e in ipairs(sm.stealable(raw, self.env.steal_own, self.env.exec_ids())) do
      by_id[e.id] = e
    end
    for id in pairs(needed) do
      -- A wrap that is not there yet gets its intent from the table the first time;
      -- after that the intent is what memory is for, and the table may no longer
      -- hold the action at all.
      if self.wrap_intent[id] == nil then
        local e = by_id[id]
        if e ~= nil and not e.wrapped then
          local originals = e.binds
          local replay = self.env.exec_for(id)
          if replay then
            originals = { { dispatcher = "exec", arg = replay, description = e.description } }
          end
          self.wrap_intent[id] = {
            keys = sm.bind_string(e.key, e.shift),
            key = e.key,
            shift = e.shift,
            originals = originals,
            description = e.description,
          }
        end
      end
      if self.wrap_intent[id] ~= nil then
        -- Wanted whether or not the bind below succeeds.
        self.desired_steals[#self.desired_steals + 1] = id
        if self.wraps[id] == nil then
          install_wrap(self, id)
        end
      end
    end
  end

  -- Hand the key to the app as Ctrl+key and consume it; any other app gets the
  -- key exactly as before. The flag that decides is the *active class's* own
  -- three-state setting, not "on somewhere": a window of an app with it off keeps
  -- its plain Super+key even while another app has it on.
  local function super_ctrl_key(key, shift)
    local w = self.env.active_window()
    if w == nil or not self.env.flag_for(self.env.window_class(w), "ctrl_as_super") then
      return { pass_event = true }
    end
    self.env.send_ctrl(key, shift, w)
  end

  function self:plan(raw, gen)
    if gen ~= self.gen then
      return
    end
    -- A bind table that did not land is not an answer: the writers that feed this
    -- (hyprctl, the panel's settings write) truncate before they write, so a read
    -- can catch half of one. Reading that as "nothing is occupied" blanked the
    -- panel's list, and reading the flags out of a torn settings file read as
    -- "Super as Ctrl is off" -- which, with the drop below, took the whole map
    -- away until the next reload: Cmd+Z stopped reaching every app.
    local valid = (raw or ""):find("modmask:%s*%d") ~= nil
    if valid then
      self.env.ensure_replay()
      self:write_occupied(raw)
      self:apply_wraps(raw)
    end
    if not self.env.flag_any("ctrl_as_super") then
      -- The user turned it off: the installed map has to go.
      self:drop()
      self.desired = {}
      self:stop_verify()
      self:write_meta(0, 0, "off", nil)
      return
    end
    local plan = valid and sm.plan(raw) or {}
    if #plan == 0 then
      -- On, but nothing planned: keep the map that is installed and let the next
      -- read try again, rather than dropping 32 binds to install none.
      return
    end
    -- A new plan replaces the last one instead of adding to it: the request that
    -- triggered it may have arrived while an earlier plan was already installed.
    self:drop()
    local wanted = {}
    local wanted_steals = {}
    local planned, bound = 0, 0
    for _, b in ipairs(plan) do
      -- The Shortcuts row owns Cmd+Shift+T once any app asks for it. A plan built
      -- from a snapshot taken before that bind landed still thinks the key is
      -- free, and a second bind would send the chord twice.
      -- A chord the pack wraps belongs to the wrap: when a wrap was just rebuilt
      -- from its intent, the fresh snapshot holds neither it nor Omarchy's original,
      -- so the plan would see the chord as free and put a plain Ctrl bind on top of
      -- the wrap -- two handlers for one key.
      local chord_id = (b.shift and "SHIFT+" or "") .. b.key
      if not (b.shift and b.key == "T" and self.env.flag_any("reopen_tab"))
          and self.wrap_intent[chord_id] == nil
          and (self.restored_chords == nil or self.restored_chords[chord_id] == nil) then
        local keys = b.shift and ("SUPER + SHIFT + " .. b.key) or ("SUPER + " .. b.key)
        -- `repeating`: a key that stays down keeps sending the chord, the way
        -- holding Cmd+D on a Mac keeps adding the next occurrence. The repeat has
        -- to be the bind's: `send_chord` hands over a whole chord and nothing
        -- held, so the app has no key of its own to repeat (and could only type
        -- the bare letter with).
        local ok, handle = self.env.bind(keys, function()
          return super_ctrl_key(b.key, b.shift)
        end, { description = sm.PREFIX .. (b.shift and " SHIFT" or "") .. " " .. b.key, repeating = true })
        planned = planned + 1
        -- Wanted, not "wanted and bound": a bind that failed is a missing chord to
        -- the reconciliation, not a requirement that quietly disappeared.
        wanted[#wanted + 1] = (b.shift and "SHIFT+" or "") .. b.key
        if ok and handle then
          bound = bound + 1
          self.binds[#self.binds + 1] = handle
        end
      end
    end
    -- A rebuild that follows a failed check is still unverified: the file keeps
    -- saying so until a check agrees, otherwise the rebuild's own "pending" would
    -- erase the only sign that something had gone wrong.
    -- The last observation is kept in the file even through a rebuild: "degraded,
    -- 85 of 86 seen" is the diagnostic, and a rebuild that wiped it would leave the
    -- next reader with a bare state.
    self:write_meta(planned, bound, self.verify_failures > 0 and "degraded" or "pending", self.last_observed)
    -- What this plan wanted, chord by chord: the reconciliation compares sets, not
    -- counts, because a lost R and a duplicated D leave the count alone.
    self.desired = wanted
    if self.desired_steals == nil then
      self.desired_steals = wanted_steals
    end
    self:start_verify()
  end

  -- Ask the compositor for its bind table and hand the text to `on_raw`, or run
  -- `on_missing` when the read never landed. The snapshot is stamped with the
  -- generation that asked for it, and every temporary path carries that generation:
  -- two attempts can overlap (a stuck read is replaced, not waited for), and a shared
  -- scratch file would let the older `hyprctl` rewrite the newer attempt's data and
  -- have it stamped with the newer generation.
  function self:snapshot(kind, on_raw, on_missing)
    -- The snapshot owns the request state: whichever ran last is the one in flight,
    -- and the flags of the previous one are cleared here. Without this, an install
    -- that replaces a running check leaves `verifying` up for good and the
    -- reconciliation stops for the rest of the session.
    self.applying = (kind == "apply")
    self.verifying = (kind == "verify")
    self.gen = self.gen + 1
    local gen = self.gen
    local path = self.env.binds_path
    if self.scratch ~= nil then
      for _, leftover in ipairs(self.scratch) do
        self.env.remove_path(leftover)
      end
    end
    local tag = tostring(self.token) .. "." .. tostring(self.gen)
    local raw = path .. "." .. tag .. ".raw"
    local stamped = path .. "." .. tag .. ".stamped"
    self.scratch = { raw, stamped }
    self.env.exec(string.format(
      "sh -c 'hyprctl binds > \"%s\" 2>/dev/null && { cat \"%s\"; printf \"@gen %s %d\\n\"; } > \"%s\" && mv \"%s\" \"%s\"'",
      raw, raw, tostring(self.token), self.gen, stamped, stamped, path))

    -- Poll for the file: the exec that writes it has not landed when the timer is
    -- set, and a missing file must not read as "nothing is bound".
    local function poll(tries)
      self.env.timer(function()
        if gen ~= self.gen then
          return
        end
        local text = self.env.read(path)
        -- Both captures are needed, so they are taken as a statement: `raw and
        -- raw:match(...)` truncates to one value, which silently dropped the stamp.
        local token, stamp
        if text ~= nil then
          token, stamp = text:match("@gen (%S+) (%d+)%s*$")
        end
        if text ~= nil and token == tostring(self.token) and stamp == tostring(gen) then
          on_raw((text:gsub("@gen %S+ %d+%s*$", "")), gen)
          return
        end
        if tries > 0 then
          poll(tries - 1)
          return
        end
        on_missing(gen)
      end, { timeout = 200, type = "oneshot" })
    end
    poll(100)
    return gen
  end

  -- The binds already installed stay until the new plan replaces them (plan drops
  -- them right before it binds), and the file on disk is left alone until a fresh
  -- one has been written: a read that never lands -- an exec that fails, a machine
  -- that is busy -- then leaves the last good plan and the last good table in
  -- place instead of none of either. Clearing both first is what made "no binds"
  -- possible with a perfectly good table on disk.
  function self:apply()
    return self:snapshot("apply", function(text, gen)
      self.applying = false
      self:plan(text, gen)
    end, function()
      self.applying = false
      -- Twenty seconds without a table: nothing was observed. The file says so
      -- instead of claiming an empty map, because the binds of an earlier plan may
      -- still be in the table.
      self:write_meta(0, 0, "unknown", nil)
    end)
  end

  -- Reconciliation: what this controller wanted, against what the compositor's
  -- table actually holds. A count proves nothing -- a lost R and a duplicated D
  -- leave the number alone -- so every wanted chord has to be there exactly once.
  --
  -- It runs asynchronously on a timer while a map is wanted, because the ways a map
  -- disappears (a reload, a failed plan, someone unbinding it) leave no event
  -- behind: without this the pack keeps its handles, believes the map is installed
  -- and every Super+key it sends as Ctrl+key silently does nothing.
  function self:check(text)
    local want, want_steal = {}, {}
    local wanted_count = 0
    for _, id in ipairs(self.desired) do
      want[id] = (want[id] or 0) + 1
      wanted_count = wanted_count + 1
    end
    for _, id in ipairs(self.desired_steals or {}) do
      want_steal[id] = (want_steal[id] or 0) + 1
      wanted_count = wanted_count + 1
    end
    local seen, seen_steal = {}, {}
    for _, e in ipairs(sm.generated_list(text)) do
      if e.kind == "steal" then
        seen_steal[e.id] = (seen_steal[e.id] or 0) + 1
      else
        seen[e.id] = (seen[e.id] or 0) + 1
      end
    end
    -- A wrap that is gone cannot be repaired by dropping a handle the compositor no
    -- longer has: the memory entry is forgotten, and the replan below rebuilds it
    -- from a fresh snapshot (where its original action is still listed).
    for id in pairs(want_steal) do
      if (seen_steal[id] or 0) == 0 and self.wraps[id] ~= nil then
        self.wraps[id] = nil
      end
    end
    local missing, duplicates = 0, 0
    local function compare(wanted, seen_set)
      for id, n in pairs(wanted) do
        local got = seen_set[id] or 0
        if got < n then
          missing = missing + (n - got)
        elseif got > n then
          duplicates = duplicates + (got - n)
        end
      end
      -- Our own bind that nothing wants any more (a chord the plan dropped) is as
      -- wrong as a missing one: the file must not call that healthy.
      for id, n in pairs(seen_set) do
        if wanted[id] == nil then
          duplicates = duplicates + n
        end
      end
    end
    compare(want, seen)
    compare(want_steal, seen_steal)
    -- Foreign binds are never counted here: the description is the only thing that
    -- says a bind is ours, and the pack does not touch anything else.
    if missing == 0 and duplicates == 0 then
      self.verify_failures = 0
      self.last_observed = wanted_count
      -- Verified means "agreed at the last check", not a standing promise: the next
      -- tick looks again.
      self:write_meta(wanted_count, wanted_count, "verified", wanted_count)
      return true
    end
    self.verify_failures = self.verify_failures + 1
    self.last_observed = wanted_count - missing
    self:write_meta(wanted_count, wanted_count, "degraded", self.last_observed)
    -- Rebuild fast a few times, then slowly. A map that cannot converge (another
    -- owner keeps taking the chord) must not replan every five seconds for the rest
    -- of the session, but giving up altogether leaves the user without the chords
    -- until some unrelated event: one attempt a minute is the middle.
    if self.verify_failures > 3 then
      self.pause_until = self.env.now() + 60
    end
    self:apply()
    return false
  end

  function self:start_verify()
    if self.verify_timer ~= nil or self.env.timer == nil then
      return
    end
    self.verify_timer = self.env.timer(function()
      self:verify()
    end, { timeout = 5000, type = "repeat" })
  end

  function self:stop_verify()
    if self.verify_timer == nil then
      return
    end
    pcall(function()
      self.verify_timer:set_enabled(false)
    end)
    self.verify_timer = nil
  end

  -- One check at a time, and not while a plan is still waiting for its own
  -- snapshot: a second read would move the generation and strand the first.
  function self:verify()
    if self.verifying or self.applying then
      return
    end
    if #self.desired == 0 or not self.env.flag_any("ctrl_as_super") then
      self:stop_verify()
      return
    end
    if self.pause_until ~= nil and self.env.now() < self.pause_until then
      return
    end
    self.verifying = true
    self:snapshot("verify", function(text)
      self.verifying = false
      self:check(text)
    end, function()
      -- The read did not land: nothing was observed, so nothing is claimed.
      self.verifying = false
      self:write_meta(#self.desired, #self.desired, "unknown", nil)
    end)
  end

  -- The map lives in Hyprland's bind table, and a reload throws that away while
  -- the replan is asynchronous. If the read that plans it never lands -- a busy
  -- machine, a second reload -- nothing ever tries again: the map stays empty for
  -- the session and Cmd+Z stops reaching every app, with no error anywhere. A
  -- window opening is the event this hangs on (and the one a session cannot go
  -- long without), and a five-second gap keeps it from hammering hyprctl while a
  -- read is in flight.
  function self:self_heal()
    if #self.binds > 0 or not self.env.flag_any("ctrl_as_super") then
      return false
    end
    -- The slow retry after repeated failures is deliberate: a window opening must
    -- not undo it. An attempt still waiting for its own read is not protected --
    -- replacing a stuck read is what this exists for, and a replacement is safe:
    -- starting it clears the request state and the new plan drops the old handles
    -- before it binds.
    if self.pause_until ~= nil and self.env.now() < self.pause_until then
      return false
    end
    local now = self.env.now()
    if now < self.retry_at then
      return false
    end
    self.retry_at = now + 5
    self:apply()
    return true
  end

  return self
end

return M
