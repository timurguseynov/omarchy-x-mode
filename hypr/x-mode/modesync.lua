-- Who owns which workspace's mode: the pack's record of them, the two places that
-- record can live, and the sequence a mode change goes through. The windows are
-- not touched here -- a mode change only says who owns them, so the placement
-- calls arrive as `env` callbacks and the whole sequence is testable in plain lua
-- (tests/unit/modesync_test.lua).
--
-- Two sources, on purpose: where Omarchy can replay a saved mode (4.5, it defines
-- o.workspace_mode) her file is the record and the pack writes nothing of its own;
-- where she cannot (4.0.x replays `hl.workspace_rule`, so a file calling
-- `o.workspace_mode` is a hard config error) the pack keeps its own file in the
-- state directory. `shared` is decided once, from the Omarchy that is running.
local M = {}

local modes = dofile(((debug.getinfo(1, "S").source or ""):match("^@(.*/)") or "./") .. "modes.lua")

-- env:
--   shared            Omarchy can replay a mode file
--   state_dir         the pack's state directory
--   write(path, text) atomic write
--   read(path) -> text|nil
--   make_dirs(path)   mkdir -p
--   workspace_dir()   the directory Omarchy keeps per-workspace files in
--
-- The effects a mode change has on windows are attached later, with `use`: the
-- record has to be restored from disk *before* the first consumer reads it
-- (the pack follows the mouse and publishes the mode long before the controller
-- gets its callbacks), so construction and wiring are two steps:
--   on_enter(id)      make the windows of `id` the pack's (null when leaving)
--   on_leave(id)
--   apply_all(place)  re-apply every workspace's mode; `place` asks for placement
--   after_change()    follow the mouse, and anything else a change implies
--   publish()         publish the active mode for the shell
function M.new(env)
  local self = { env = env, table = env.mode_table or modes.new(), effects = {} }

  function self:path()
    return self.env.state_dir .. "/workspace-modes.lua"
  end

  function self:persist()
    if self.env.shared then
      return
    end
    self.env.make_dirs(self.env.state_dir)
    self.env.write(self:path(), modes.dump(self.table))
  end

  -- The pack's own file is read only where it is also the writer; on 4.5 Omarchy's
  -- saved files were already loaded before this module existed, and a second load
  -- would be a second truth.
  function self:load()
    if self.env.shared then
      return false
    end
    local text = self.env.read(self:path())
    if text == nil then
      return false
    end
    modes.load_text(self.table, text)
    return true
  end

  -- The windows are not this module's business, and they are not known yet when
  -- the record is restored: the callbacks arrive here, once, after the rest of
  -- the config has defined them.
  function self:use(effects)
    self.effects = effects
    return self
  end

  function self:mode(id)
    return modes.get(self.table, id)
  end

  function self:default_mode()
    return self.table.default
  end

  function self:is_xmode(id)
    return modes.is_xmode(self.table, id)
  end

  -- The raw records, without any of the effects: used while claiming an install's
  -- workspaces, where the caller decides when windows move.
  function self:set(id, mode)
    modes.set(self.table, id, mode)
  end

  function self:set_default(mode)
    modes.set_default(self.table, mode)
  end

  -- Omarchy's own file for a workspace, so her bar, her current-layout script and
  -- the next login follow the mode. Only where she can replay it: on 4.0.x the
  -- call is a config error, and the pack's record is the only one kept.
  function self:write_workspace(id, mode)
    if not self.env.shared then
      return
    end
    local dir = self.env.workspace_dir()
    self.env.make_dirs(dir)
    self.env.write(dir .. "/" .. tostring(id) .. ".lua",
      string.format('o.workspace_mode({ workspace = "%s", mode = "%s" })\n', tostring(id), mode))
  end

  function self:apply(id, mode)
    modes.set(self.table, id, mode)
    self:persist()
    if modes.is_xmode(self.table, id) then
      self.effects.on_enter(id)
    else
      self.effects.on_leave(id)
    end
    self.effects.after_change()
    -- The dock watches the published mode, and switching the mode of the workspace
    -- already on screen fires no workspace.active: it has to be published here.
    self.effects.publish()
  end

  function self:apply_default(mode)
    modes.set_default(self.table, mode)
    self:persist()
    -- Every workspace without a mode of its own just changed. The windows keep
    -- their boxes: this is not a placement, only who owns them.
    self.effects.apply_all(false)
    self.effects.after_change()
    -- Changing the default does not move the focus, so workspace.active will not
    -- publish it.
    self.effects.publish()
  end

  -- Omarchy's setter, wrapped: her own call still runs first, and a failure there
  -- stays a failure. What she cannot do -- keep the pack's record, move windows --
  -- happens after it.
  function self:wrap_omarchy(original, on_call, on_done)
    if type(original) ~= "function" then
      return nil
    end
    return function(spec)
      on_call()
      local ok, err = pcall(original, spec)
      on_done()
      if not ok then
        error(err, 0)
      end
      if type(spec) ~= "table" then
        return
      end
      if spec.default ~= nil then
        self:apply_default(spec.default)
        return
      end
      local id = tonumber(spec.workspace)
      if id == nil or spec.mode == nil then
        return
      end
      self:apply(id, spec.mode)
    end
  end

  self:load()
  return self
end

return M
