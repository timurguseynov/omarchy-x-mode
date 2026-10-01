-- The config is not only loaded by Hyprland: Omarchy's keybindings scan
-- (`omarchy-menu-keybindings`) dofiles hyprland.lua with a stub `hl` whose every
-- field is a callable proxy that answers any index, so it can read the binds
-- without a compositor. A query result there is that proxy and not a list, and
-- `ipairs` walks it forever -- that hung the menu with three `lua` processes
-- pinned at 100% CPU until the scan was stopped.
--
-- This loads the real config under the same stub and fails if it does not
-- finish. The runner points HOME and X_MODE_STATE at a throwaway directory, so
-- nothing here touches the session.
local repo = os.getenv("X_MODE_REPO") or "."

local noop
noop = setmetatable({}, {
  __index = function() return noop end,
  __call = function() return noop end,
})

local function dsp_proxy()
  return setmetatable({}, { __index = function() return function() return noop end end })
end

hl = setmetatable({
  dsp = dsp_proxy(),
  bind = function() return noop end,
  get_config = function() return nil end,
}, { __index = function() return noop end })

o = {
  bind = function(...) return hl.bind(...) end,
  window = function() end,
  exec_on_start = function() end,
}

-- A count hook: a proxy loop breaks out with a traceback instead of spinning
-- until the runner gives up.
local start = os.clock()
debug.sethook(function()
  if os.clock() - start > 10 then
    error(debug.traceback("the config did not finish under the scan stub", 2), 0)
  end
end, "", 100000)

local ok, err = pcall(dofile, repo .. "/hypr/x-mode/x-mode.lua")
debug.sethook()

if not ok then
  io.stderr:write("FAIL scan_stub: " .. tostring(err) .. "\n")
  os.exit(1)
end
print("scan stub ok")
