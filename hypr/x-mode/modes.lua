-- Workspace modes: the pack's side of Omarchy's `o.workspace_mode`.
--
-- Omarchy keeps a mode per workspace -- dwindle, scrolling, floating, and the one
-- the pack adds, xmode -- in $XDG_STATE_HOME/omarchy/workspace-layouts:
--
--   <id>.lua      o.workspace_mode({ workspace = "3", mode = "xmode" })
--   default.lua   o.workspace_mode({ default = "floating" })
--
-- That directory is replayed while the config loads (default.hypr.workspace-layouts),
-- and the pack is required last, so it cannot learn the modes by wrapping that
-- function alone: it reads the same files at load and wraps the function for
-- everything that changes afterwards. Reading and writing the files stays in
-- x-mode.lua; what is here is everything that can be decided without a
-- compositor, so tests/unit can cover it (tests/unit/modes_test.lua).
--
-- The pack is on only where the mode is xmode. Every other mode belongs to
-- Omarchy: tiling, scrolling, its own floating. A workspace cannot be floating
-- and xmode at once. The titlebar plugin stays the pack's: it draws Omarchy's
-- bar on a floating workspace and its own on xmode, and does not load her
-- titlebars.so beside itself.
local M = {}

M.XMODE = "xmode"

-- The last workspace id a numeric range can name. Hyprland's own sentinel, and
-- what Omarchy's floating ranges use.
M.LAST = 2147483647

function M.new()
  return { default = nil, workspaces = {} }
end

-- One saved file, as the call it holds. Returns
--   { workspace = <id>, mode = "xmode" }  for a workspace file,
--   { default = "floating" }              for default.lua,
--   nil                                   for anything else.
-- Both arguments are quoted in the file and both are read unquoted here, so a
-- hand-written `mode = "xmode"` and the script's own spelling agree.
function M.parse_saved(text)
  local src = tostring(text or "")

  local default = src:match('default%s*=%s*"(%a+)"')
  if default ~= nil then
    return { default = default }
  end

  local mode = src:match('mode%s*=%s*"(%a+)"')
  if mode == nil then
    return nil
  end

  local workspace = src:match('workspace%s*=%s*"?([%w_%-]+)"?')
  if workspace == nil or tonumber(workspace) == nil then
    -- A named workspace reports a negative id and keeps whatever state a window
    -- arrived with (Omarchy's own rule); it cannot hold a mode.
    return nil
  end

  return { workspace = tonumber(workspace), mode = mode }
end

-- Apply one parsed file to the state. A workspace mode replaces the workspace's
-- own, the default replaces the default; nothing is remembered for a mode the
-- pack was not told about -- the state holds whatever Omarchy's table holds, and
-- Omarchy is what replays it.
function M.load(state, saved)
  if saved == nil then
    return state
  end

  if saved.default ~= nil then
    state.default = saved.default
  elseif saved.workspace ~= nil and saved.mode ~= nil then
    state.workspaces[saved.workspace] = saved.mode
  end

  return state
end

function M.set(state, workspace, mode)
  local id = tonumber(workspace)
  if id == nil or type(mode) ~= "string" or mode == "" then
    return state
  end

  state.workspaces[id] = mode
  return state
end

function M.set_default(state, mode)
  if type(mode) ~= "string" or mode == "" then
    return state
  end

  state.default = mode
  return state
end

-- The mode of a workspace: its own, or the default for one without. A named
-- workspace (a negative id) holds no mode of its own.
function M.get(state, workspace)
  local id = tonumber(workspace)
  if id == nil then
    return state.default
  end

  if id >= 1 then
    local own = state.workspaces[id]
    if own ~= nil then
      return own
    end
  end

  return state.default
end

function M.is_xmode(state, workspace)
  return M.get(state, workspace) == M.XMODE
end

-- The xmode workspaces as contiguous id ranges, for the window rules that make
-- them float: a rule matches on `workspace = "r[from-to]"`, so a set has to be
-- spelled as ranges. With xmode as the default, every workspace that is not
-- explicitly another mode is in it, which is the same shape as the ranges
-- Omarchy builds for its own floating workspaces.
function M.ranges(state)
  local tiled = {}
  for id, mode in pairs(state.workspaces) do
    local n = tonumber(id)
    if n ~= nil and n >= 1 and mode ~= M.XMODE then
      table.insert(tiled, n)
    end
  end
  table.sort(tiled)

  local out = {}
  if state.default == M.XMODE then
    local from = 1
    for _, n in ipairs(tiled) do
      if n > from then
        table.insert(out, { from, n - 1 })
      end
      from = n + 1
    end
    table.insert(out, { from, M.LAST })
    return out
  end

  local mine = {}
  for id, mode in pairs(state.workspaces) do
    local n = tonumber(id)
    if n ~= nil and n >= 1 and mode == M.XMODE then
      table.insert(mine, n)
    end
  end
  table.sort(mine)

  local out = {}
  for _, n in ipairs(mine) do
    local last = out[#out]
    if last ~= nil and last[2] == n - 1 then
      last[2] = n
    else
      table.insert(out, { n, n })
    end
  end

  return out
end

-- One rule match string per range, e.g. "r[4-2147483647]".
function M.range_matches(state)
  local out = {}
  for _, r in ipairs(M.ranges(state)) do
    table.insert(out, string.format("r[%d-%d]", r[1], r[2]))
  end
  return out
end

return M
