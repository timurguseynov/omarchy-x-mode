-- The window-rule bookkeeping: which rules are enabled, which are dropped, and the
-- per-workspace gap rules. No compositor: every call is recorded by a fake env.
local repo = os.getenv("X_MODE_REPO") or "."
local rules = dofile(repo .. "/hypr/x-mode/rules.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
  end
end

local function env(over)
  local e = { calls = {}, gaps = {}, clears = {}, wanted = {} }
  function e.rule(name, cls, effect, on)
    e.calls[#e.calls + 1] = name .. cls .. ":" .. effect .. ":" .. tostring(on)
  end
  function e.gap_rule(id) e.gaps[#e.gaps + 1] = id end
  function e.gap_clear(id) e.clears[#e.clears + 1] = id end
  function e.want_no_gap(id) return e.wanted[id] == true end
  for k, v in pairs(over or {}) do e[k] = v end
  return e
end

-- The effects are the plugin's contract: these strings are what hyprbars reads.
check("effect.nobar", rules.effects.nobar.effect, "hyprbars:no_bar")
check("effect.always", rules.effects.always.effect, "hyprbars:always_tabbar")
check("effect.compact", rules.effects.compact.effect, "hyprbars:compact_tabs")
check("prefix.nobar", rules.effects.nobar.prefix, "x-mode-nobar-")
check("prefix.always", rules.effects.always.prefix, "x-mode-always-tabbar-")
check("prefix.compact", rules.effects.compact.prefix, "x-mode-compact-tabs-")

-- Chrome off: one rule, on. Nothing else is touched.
local e1 = env()
local r1 = rules.new(e1)
r1:apps({ foot = { chrome = false } })
check("apps.chrome-off", table.concat(e1.calls, ","), "x-mode-nobar-foot:hyprbars:no_bar:true")

-- A second pass with the same settings calls nothing: the bookkeeping is what keeps
-- a settings refresh from re-setting every rule on every panel click.
e1.calls = {}
r1:apps({ foot = { chrome = false } })
check("apps.idempotent", #e1.calls, 0)

-- Turning chrome back on drops the rule.
e1.calls = {}
r1:apps({ foot = { chrome = true } })
check("apps.chrome-on-drops", table.concat(e1.calls, ","), "x-mode-nobar-foot:hyprbars:no_bar:false")

-- Chrome off wins over the other two: an app with no bar gets no tabbar rules.
local e2 = env()
local r2 = rules.new(e2)
r2:apps({ zed = { chrome = false, always_tabbar = true, compact_tabs = true } })
local text2 = table.concat(e2.calls, ",")
check("apps.chrome-off-wins-nobar", text2:find("nobar-zed:hyprbars:no_bar:true", 1, true) ~= nil, true)
check("apps.chrome-off-wins-always", text2:find("always-tabbar-zed", 1, true), nil)
check("apps.chrome-off-wins-compact", text2:find("compact-tabs-zed", 1, true), nil)

-- Without chrome off, both other flags are set, each with its own rule.
local e3 = env()
local r3 = rules.new(e3)
r3:apps({ kitty = { always_tabbar = true, compact_tabs = true } })
local text3 = table.concat(e3.calls, ",")
check("apps.always-set", text3:find("x-mode-always-tabbar-kitty:hyprbars:always_tabbar:true", 1, true) ~= nil, true)
check("apps.compact-set", text3:find("x-mode-compact-tabs-kitty:hyprbars:compact_tabs:true", 1, true) ~= nil, true)

-- The case-sensitivity fix lives in set_rule's pattern, so the class is passed as it
-- was written: "Org.Mozilla.Thunderbird" must not be lowercased here.
local e4 = env()
local r4 = rules.new(e4)
r4:apps({ ["Org.Mozilla.Thunderbird"] = { chrome = false } })
check("apps.class-case-kept", e4.calls[1], "x-mode-nobar-Org.Mozilla.Thunderbird:hyprbars:no_bar:true")

-- Gap rules follow the switch: a workspace that wants one gets it, one that does not
-- is cleared, and a workspace that disappeared has its rule removed.
local e5 = env()
e5.wanted = { [1] = true, [2] = false }
local r5 = rules.new(e5)
r5:gaps({ 1, 2 })
check("gaps.set", table.concat(e5.gaps, ","), "1")
check("gaps.cleared-when-off", table.concat(e5.clears, ","), "2")

-- The workspace is gone from the list: the rule must not survive it.
e5.gaps = {}
e5.clears = {}
r5:gaps({ 2 })
-- The workspace in the list is settled first (2), the stale one after (1):
-- the same order the config had.
check("gaps.stale-cleared", table.concat(e5.clears, ","), "2,1")
check("gaps.no-set", #e5.gaps, 0)

-- A repeated id and a workspace below 1 are not rules.
local e6 = env()
e6.wanted = { [1] = true }
local r6 = rules.new(e6)
r6:gaps({ 1, 1, 0, -3 })
check("gaps.dedup", #e6.gaps, 1)
check("gaps.ignores-special", #e6.clears, 0)

-- A rule created from a live event -- entering a workspace, a workspace being
-- created -- goes through the same registry, so a workspace that disappears before
-- the next sync is still cleaned up.
local e7 = env()
local r7 = rules.new(e7)
e7.wanted = { [4] = true }
r7:gap_open(4)
check("live.opened", table.concat(e7.gaps, ","), "4")
e7.gaps = {}
e7.clears = {}
r7:gaps({})
check("live.stale-cleared", table.concat(e7.clears, ","), "4")

-- Closing it by hand removes it from the registry too: a second close is not a
-- second call into the compositor.
local e8 = env()
local r8 = rules.new(e8)
r8:gap_open(5)
r8:gap_close(5)
e8.clears = {}
r8:gaps({})
check("live.closed-once", #e8.clears, 0)

if failures > 0 then
  os.exit(1)
end
print("rules ok")
