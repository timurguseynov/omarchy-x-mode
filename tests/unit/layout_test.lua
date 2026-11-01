-- layout.lua's pure half, so this runs with plain lua: no Hyprland, no
-- compositor. plan_arrange is the entire decision an arrange makes -- which
-- window goes to which side -- so it is the part that has to be provable on its
-- own. The appliers below it ask the plugin for geometry and need a compositor;
-- they are covered by the nest.
local repo = os.getenv("X_MODE_REPO") or "."
local layout = dofile(repo .. "/hypr/x-mode/layout.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    io.stderr:write(string.format("FAIL %s: got %s, want %s\n", name, tostring(got), tostring(want)))
    failures = failures + 1
  end
end

-- The shuffle is the caller's, so the deal order is fixed here. Returning the
-- index is the identity (no swap); returning 1 is one swap, which reverses.
local in_order = function(n)
  return n
end
local swap = function()
  return 1
end
local function kinds(plan)
  local out = {}
  for _, deal in ipairs(plan) do
    out[#out + 1] = deal.kind
  end
  return table.concat(out, ",")
end
local function keys(plan)
  local out = {}
  for _, deal in ipairs(plan) do
    out[#out + 1] = deal.key
  end
  return table.concat(out, ",")
end

-- Two apps on one workspace alternate, starting left.
local plan = layout.plan_arrange({
  { key = "a", class = "foot", space = 1 },
  { key = "b", class = "kitty", space = 1 },
}, in_order)
check("two apps alternate", kinds(plan), "left,right")
check("keys come back unchanged", keys(plan), "a,b")

-- One app is one group, so its second window is not dealt again: the deal would
-- put it on the other half and the group would then be yanked back.
plan = layout.plan_arrange({
  { key = "a1", class = "foot", space = 1 },
  { key = "a2", class = "foot", space = 1 },
  { key = "b1", class = "kitty", space = 1 },
}, in_order)
check("one window per class", kinds(plan), "left,right")
check("the class' second window is dropped", keys(plan), "a1,b1")

-- Each workspace is split on its own, so a window never changes workspace.
-- A workspace with a single group has nothing to be on a side of: it is centred
-- (the plugin's almost-maximize box), and only a second group starts the
-- left/right alternation.
plan = layout.plan_arrange({
  { key = "a", class = "foot", space = 1 },
  { key = "b", class = "kitty", space = 2 },
  { key = "c", class = "alacritty", space = 2 },
}, in_order)
check("a lone group is centred", kinds(plan), "almost-maximize,left,right")
check("space order is the list order", keys(plan), "a,b,c")

-- Namely: one group on one workspace is centred, not left.
plan = layout.plan_arrange({
  { key = "a", class = "foot", space = 1 },
}, in_order)
check("one group is centred", kinds(plan), "almost-maximize")

-- The same class on two workspaces is two windows (the class key includes the
-- space): one group per space, and each space centres its own.
plan = layout.plan_arrange({
  { key = "a1", class = "foot", space = 1 },
  { key = "a2", class = "foot", space = 2 },
}, in_order)
check("one group on each of two spaces is centred twice", kinds(plan), "almost-maximize,almost-maximize")

-- A class we cannot name is not something to deal (an unknown class could be
-- anything); a window with no workspace is still a window, and alone it centres.
plan = layout.plan_arrange({
  { key = "x", class = "", space = 1 },
  { key = "y", class = "foot", space = nil },
}, in_order)
check("no class, no deal", kinds(plan), "almost-maximize")

-- The shuffle moves the order, and the sides follow the shuffled order.
plan = layout.plan_arrange({
  { key = "a", class = "foot", space = 1 },
  { key = "b", class = "kitty", space = 1 },
}, swap)
check("a swap puts the other app left", keys(plan), "b,a")
check("sides follow the shuffled order", kinds(plan), "left,right")

-- An empty list is an empty plan, not an error: the arrange runs on a desktop
-- with no windows open.
check("empty", #layout.plan_arrange({}, in_order), 0)

-- A space is never left half-empty by the alternation crossing a boundary: with
-- four apps on one space it is two left, two right.
plan = layout.plan_arrange({
  { key = "a", class = "aa", space = 1 },
  { key = "b", class = "bb", space = 1 },
  { key = "c", class = "cc", space = 1 },
  { key = "d", class = "dd", space = 1 },
}, in_order)
check("four apps split evenly", kinds(plan), "left,right,left,right")

-- The one way the pack writes a state file. An in-place open truncates first,
-- so a writer that dies between the open and the write leaves an empty file and
-- every reader takes that as the state -- which is how the panel's list of keys
-- to replace vanished while an install ran on a loaded machine. Written whole or
-- not at all.
local tmpdir = (os.getenv("HOME") or "/tmp") .. "/write-atomic-test"
os.execute("rm -rf '" .. tmpdir .. "' && mkdir -p '" .. tmpdir .. "'")
local target = tmpdir .. "/state.json"

check("write_atomic.new", layout.write_atomic(target, '{"a":1}\n'), true)
local f = io.open(target, "r")
check("write_atomic.content", f and f:read("*a"), '{"a":1}\n')
if f then f:close() end

check("write_atomic.replaces", layout.write_atomic(target, '{"a":2}\n'), true)
f = io.open(target, "r")
check("write_atomic.replaced", f and f:read("*a"), '{"a":2}\n')
if f then f:close() end
check("write_atomic.no-tmp-left", io.open(target .. ".tmp", "r"), nil)

-- A write that cannot land leaves the old file alone and no temp behind.
check("write_atomic.fails", layout.write_atomic(tmpdir .. "/missing/dir/x", "x"), false)
f = io.open(target, "r")
check("write_atomic.old-intact", f and f:read("*a"), '{"a":2}\n')
if f then f:close() end
os.execute("rm -rf '" .. tmpdir .. "'")

if failures > 0 then
  os.exit(1)
end
print("layout ok")
