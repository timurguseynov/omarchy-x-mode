-- Undeclared globals, from the bytecode. A missing `local` turns a name into a
-- nil global that `luac -p` cannot see and that only fails when a callback runs,
-- which is how a deleted `local X_MODE_STATE` reached a live session.
--
-- Locals never appear as GETTABUP, so any *read* of a name the same file never
-- assigns (SETTABUP) and that is not provided by Lua or by Hyprland/Omarchy is an
-- undeclared global. Usage: lua tests/globals.lua [file.lua ...]
local provided = {
  -- Lua's own names.
  assert = true, collectgarbage = true, dofile = true, error = true, getmetatable = true,
  ipairs = true, load = true, loadfile = true, next = true, pairs = true, pcall = true,
  print = true, rawequal = true, rawget = true, rawlen = true, rawset = true, require = true,
  select = true, setmetatable = true, tonumber = true, tostring = true, type = true,
  warn = true, xpcall = true, unpack = true, _G = true, _ENV = true, _VERSION = true, arg = true,
  coroutine = true, debug = true, io = true, math = true, os = true, package = true,
  string = true, table = true, utf8 = true,
  -- Supplied by the compositor and by Omarchy's config, not by the pack.
  hl = true,
  o = true,
}

-- Reads only: a read of a name the compiler did not resolve to a local or upvalue
-- is a global read. Locals never appear here, which is what makes this check able
-- to see a deleted `local`.
local function global_reads(output)
  local names = {}
  for line in output:gmatch("[^\n]+") do
    if line:find("GETTABUP", 1, true) then
      local name = line:match('_ENV "([%w_]+)"')
      if name then
        names[name] = true
      end
    end
  end
  return names
end

-- The globals a file declares, from the source: a top-level `function name` or
-- `name = ...`. A `local function name` is not one, and that is the point --
-- a file that only says `local function as_list` and then reads a global
-- `as_list` has lost its declaration.
local function declared_globals(path)
  local names = {}
  local file = io.open(path, "r")
  if file == nil then
    return names
  end
  for line in file:lines() do
    local fn = line:match("^function%s+([%w_]+)%s*%(")
    local assigned = line:match("^([%w_]+)%s*=")
    if fn then
      names[fn] = true
    end
    if assigned then
      names[assigned] = true
    end
  end
  file:close()
  return names
end

local function listing(path)
  local pipe = io.popen("luac -l " .. string.format("%q", path) .. " 2>&1")
  if pipe == nil then
    return nil, "could not run luac"
  end
  local out = pipe:read("*a") or ""
  local ok = pipe:close()
  if not ok then
    return nil, out
  end
  return out
end

local problems = 0
local files = 0
for _, path in ipairs(arg) do
  files = files + 1
  local out, err = listing(path)
  if out == nil then
    problems = problems + 1
    print(string.format("%s: %s", path, (err or ""):gsub("%s+$", "")))
  else
    local declared = declared_globals(path)
    local reported = false
    local seen = {}
    for name in pairs(global_reads(out)) do
      if not provided[name] and not declared[name] and not seen[name] then
        seen[name] = true
        reported = true
        problems = problems + 1
        print(string.format("%s: reads the global %q, which the file never declares -- a missing local?", path, name))
      end
    end
    if not reported then
      seen = nil
    end
  end
end

if files == 0 then
  print("usage: lua tests/globals.lua <file.lua> [more.lua ...]")
  os.exit(2)
end
if problems > 0 then
  os.exit(1)
end
os.exit(0)
