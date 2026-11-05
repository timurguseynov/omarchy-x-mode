-- The window rules the app settings drive: no titlebar, always-tabbar, compact tabs,
-- and the per-workspace gap rules of the "No gaps" switch. Which rule to enable and
-- which to drop is decided here; the calls themselves come from `env`, so the
-- bookkeeping -- the part that gets out of step with the desktop -- is testable in
-- plain lua.
--
-- The rule names and effects are the plugin's contract: hyprbars reads
-- `hyprbars:no_bar`, `hyprbars:always_tabbar`, `hyprbars:compact_tabs`, and a rename
-- on one side only is a setting that silently does nothing.
local M = {}

local settings = dofile(((debug.getinfo(1, "S").source or ""):match("^@(.*/)") or "./") .. "settings.lua")

-- The effect each rule carries, and the prefix of its name.
M.effects = {
  nobar = { prefix = "x-mode-nobar-", effect = "hyprbars:no_bar" },
  always = { prefix = "x-mode-always-tabbar-", effect = "hyprbars:always_tabbar" },
  compact = { prefix = "x-mode-compact-tabs-", effect = "hyprbars:compact_tabs" },
}

-- env:
--   rule(name, cls, effect, on)  enable or disable one window rule
--   gap_rule(id)                 the no-gap rule for one workspace
--   gap_clear(id)                remove that workspace's rule
--   want_no_gap(id)              whether this workspace should have it
function M.new(env)
  local self = { env = env, applied = { nobar = {}, always = {}, compact = {} }, gap_set = {} }

  -- The gap callbacks arrive later than the chrome ones: the config sets the chrome
  -- rules while it is still building, and the gap rules only once the workspace
  -- helpers exist. env is read at call time, so they are added here.
  function self:use(fns)
    for k, v in pairs(fns or {}) do
      self.env[k] = v
    end
    return self
  end

  -- Bring the rules in line with the settings: enable what is new, disable what is
  -- gone, and call nothing for what has not changed. The applied sets are what the
  -- last pass wanted, not what it managed to set, which is the same thing the
  -- config did before this moved here.
  function self:apps(cfg)
    for key, spec in pairs(M.effects) do
      local wanted = select(({ nobar = 1, always = 2, compact = 3 })[key], settings.desired_rules(cfg))
      local add, drop = settings.rule_diff(wanted, self.applied[key])
      for _, cls in ipairs(add) do
        self.env.rule(spec.prefix, cls, spec.effect, true)
      end
      for _, cls in ipairs(drop) do
        self.env.rule(spec.prefix, cls, spec.effect, false)
      end
      self.applied[key] = wanted
    end
  end

  -- The "No gaps" switch: every workspace in `ids` gets the rule it wants, and the
  -- rule of a workspace that is gone is removed. `ids` is built by the caller, which
  -- is the only part that has to ask the compositor.
  -- The one owner of the registry. A rule can be created from a live event too --
  -- entering a workspace, a workspace being created -- and that path has to record
  -- itself here, or the rule of a workspace that disappears is never removed.
  function self:gap_open(id)
    local n = tonumber(id)
    if n == nil or n < 1 then
      return false
    end
    self.env.gap_rule(n)
    self.gap_set[n] = true
    return true
  end

  function self:gap_close(id)
    local n = tonumber(id)
    if n == nil then
      return false
    end
    self.env.gap_clear(n)
    self.gap_set[n] = nil
    return true
  end

  function self:gaps(ids)
    local seen = {}
    for _, id in ipairs(ids or {}) do
      local n = tonumber(id)
      if n ~= nil and n >= 1 and not seen[n] then
        seen[n] = true
        if self.env.want_no_gap(n) then
          self:gap_open(n)
        else
          self:gap_close(n)
        end
      end
    end
    for id in pairs(self.gap_set) do
      if not seen[id] then
        self:gap_close(id)
      end
    end
  end

  return self
end

return M
