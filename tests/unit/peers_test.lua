-- The same-app peer rule, with a fake window list: which window a new one joins,
-- and what the cheap "is there a peer" answer costs. No Hyprland.
local repo = os.getenv("X_MODE_REPO") or "."
local peers = dofile(repo .. "/hypr/x-mode/peers.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
  end
end

-- A window list with the accessors the event loop would supply, and counters for
-- the calls that cost something.
local function env(windows, over)
  local e = { refreshed = {}, skipped = {}, refresh_calls = 0 }
  function e.class(w) return w.class end
  function e.ws(w) return w.ws end
  function e.skip(w) e.skipped[#e.skipped + 1] = w.address; return w.skip == true end
  function e.refresh(w)
    e.refresh_calls = e.refresh_calls + 1
    e.refreshed[#e.refreshed + 1] = w and w.address
    return w
  end
  for k, v in pairs(over or {}) do e[k] = v end
  e.windows = windows
  return e
end

local new = { address = "a1", class = "foot", ws = 3 }
local grouped = { address = "a2", class = "foot", ws = 3, group = { current = { address = "a3", class = "foot", ws = 3 } } }
local bare = { address = "a4", class = "foot", ws = 3 }
local other_ws = { address = "a5", class = "foot", ws = 4 }
local other_class = { address = "a6", class = "kitty", ws = 3 }

-- A group wins even when a bare window comes first in the list: the order of the
-- compositor's list must not decide which window is joined.
local e1 = env()
local peer = peers.find(new, { bare, grouped, other_ws, other_class }, e1)
check("find.prefers-group", peer.address, "a3")

-- The group's current window is what gets joined, and it is refreshed for that.
check("find.refreshes-current", e1.refreshed[#e1.refreshed], "a3")

-- No group: the first matching bare window is the fallback.
local e2 = env()
check("find.fallback", peers.find(new, { bare, other_ws, other_class }, e2).address, "a4")

-- Nothing to join.
check("find.none", peers.find(new, { other_ws, other_class }, env()), nil)
check("find.empty", peers.find(new, {}, env()), nil)

-- The window itself is never its own peer.
check("find.not-itself", peers.find(new, { new }, env()), nil)

-- A skipped window is not a candidate, and the skip is asked of the candidate.
local skipped = { address = "a7", class = "foot", ws = 3, skip = true }
check("find.skipped", peers.find(new, { skipped }, env()), nil)

-- exists(): the cheap answer. It must not refresh anything and must not look into
-- groups -- that is the work window.open_early never uses.
local e3 = env()
check("exists.true", peers.exists(new, { bare }, e3), true)
check("exists.no-refresh", e3.refresh_calls, 0)
local e4 = env()
check("exists.grouped", peers.exists(new, { grouped }, e4), true)
check("exists.grouped-no-refresh", e4.refresh_calls, 0)
check("exists.false", peers.exists(new, { other_ws, other_class }, env()), false)
check("exists.not-itself", peers.exists(new, { new }, env()), false)

-- A window that is itself ungroupable is never hidden waiting for a peer, even
-- when the list is full of matching candidates: the entry check find_peer did is
-- part of this answer too.
local hidden_self = { address = "a8", class = "foot", ws = 3, skip = true }
check("exists.self-skipped", peers.exists(hidden_self, { bare, grouped }, env()), false)

-- The answer agrees with find() on the same list: exists is true exactly when
-- find would return a window.
for _, list in ipairs({ { bare }, { grouped }, { other_ws }, {}, { skipped } }) do
  local found = peers.find(new, list, env()) ~= nil
  local there = peers.exists(new, list, env())
  check("agree." .. #list, there, found)
end

if failures > 0 then
  os.exit(1)
end
print("peers ok")
