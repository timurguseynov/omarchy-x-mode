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
--   write(name, text)                     remove(name)
--   read(path) -> text|nil                exec(cmd)             timer(fn, opts)
--   now() -> seconds                      binds_path            steal_own
function M.new(env)
  local self = { env = env, gen = 0, binds = {}, wraps = {}, retry_at = 0 }

  function self:drop()
    for _, handle in ipairs(self.binds) do
      self.env.release(handle)
    end
    self.binds = {}
  end

  -- What the plan produced, next to the files the panel and the tests read. The
  -- bind table itself is the nest's most contended socket -- the compositor, the
  -- harness's own IPC proxy and this read all go through it -- so "did the plan
  -- make binds" has to be answerable without asking it again. Written on every
  -- pass, including the ones that bind nothing: a file that only a successful
  -- plan rewrites keeps the last good numbers through a map that has been
  -- dropped, which is how a dead Super as Ctrl looked healthy.
  function self:write_meta(planned, bound)
    self.env.write("super-ctrl.json", string.format('{"planned":%d,"bound":%d,"keys":%d}\n', planned, bound, #self.binds))
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

  function self:drop_wrap(id)
    local wrap = self.wraps[id]
    if wrap == nil then
      return
    end
    self.env.release(wrap.handle)
    for _, orig in ipairs(wrap.originals) do
      self.env.restore(wrap.keys, orig)
    end
    self.wraps[id] = nil
  end

  -- Keys Omarchy binds that the pack has taken over, so an app that wants Ctrl
  -- gets it while every other app keeps Omarchy's action.
  function self:apply_wraps(raw)
    local needed = self.env.needed_ids()
    for id in pairs(self.wraps) do
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
      if self.wraps[id] == nil then
        local e = by_id[id]
        if e ~= nil and not e.wrapped then
          local keys = sm.bind_string(e.key, e.shift)
          local originals = e.binds
          local replay = self.env.exec_for(id)
          if replay then
            originals = { { dispatcher = "exec", arg = replay, description = e.description } }
          end
          self.env.unbind(keys)
          local code = sm.key_code(e.key)
          if code ~= nil then
            local ck = e.shift and ("SUPER + SHIFT + code:" .. tostring(code)) or ("SUPER + code:" .. tostring(code))
            self.env.unbind(ck)
          end
          local key, shift = e.key, e.shift
          local ok, handle = self.env.bind(keys, function()
            local w = self.env.active_window()
            if w ~= nil and self.env.key_stolen(self.env.window_class(w), key, shift) then
              self.env.send_ctrl(key, shift, w)
              return
            end
            for _, orig in ipairs(originals) do
              self.env.replay(orig)
            end
          end, { description = sm.steal_desc(id, e.description) })
          if ok and handle then
            self.wraps[id] = { keys = keys, originals = originals, handle = handle }
          end
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
      self:write_meta(0, 0)
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
    local planned, bound = 0, 0
    for _, b in ipairs(plan) do
      -- The Shortcuts row owns Cmd+Shift+T once any app asks for it. A plan built
      -- from a snapshot taken before that bind landed still thinks the key is
      -- free, and a second bind would send the chord twice.
      if not (b.shift and b.key == "T" and self.env.flag_any("reopen_tab")) then
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
        if ok and handle then
          bound = bound + 1
          self.binds[#self.binds + 1] = handle
        end
      end
    end
    self:write_meta(planned, bound)
  end

  -- Poll for the file: the exec that writes it has not landed when the timer is
  -- set, and a missing file must not read as "nothing is bound".
  local function read_binds(path, tries, gen)
    self.env.timer(function()
      if gen ~= self.gen then
        return
      end
      local raw = self.env.read(path)
      if raw ~= nil then
        self:plan(raw, gen)
        return
      end
      if tries > 0 then
        read_binds(path, tries - 1, gen)
        return
      end
      -- Twenty seconds without a table: report what is actually bound instead of
      -- leaving the last good numbers in a file the panel and the tests read as
      -- "the plan is fine".
      self:write_meta(0, 0)
    end, { timeout = 200, type = "oneshot" })
  end

  -- The binds already installed stay until the new plan replaces them (plan drops
  -- them right before it binds), and the file on disk is left alone until a fresh
  -- one has been written: a read that never lands -- an exec that fails, a machine
  -- that is busy -- then leaves the last good plan and the last good table in
  -- place instead of none of either. Clearing both first is what made "no binds"
  -- possible with a perfectly good table on disk.
  function self:apply()
    self.gen = self.gen + 1
    local path = self.env.binds_path
    self.env.exec("sh -c 'hyprctl binds > \"" .. path .. ".tmp\" 2>/dev/null && mv \"" .. path .. ".tmp\" \"" .. path .. "\"'")
    -- 200ms a try. `hyprctl binds` writes a table of several hundred lines, and
    -- the budget has to cover a loaded machine: ten tries (two seconds) ran out
    -- under a full suite, the read gave up, and no Super-as-Ctrl bind was ever
    -- made -- which looks exactly like a plan that refused to run. Twenty seconds,
    -- because a nest under load has been measured taking more than ten.
    read_binds(path, 100, self.gen)
    return self.gen
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
