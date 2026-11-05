-- The tab decisions: may this window be a tab, are these two already together, and
-- what to do with a new window and its peer. No compositor.
local repo = os.getenv("X_MODE_REPO") or "."
local grouping = dofile(repo .. "/hypr/x-mode/grouping.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
  end
end

local function env(over)
  local e = {
    class_of = function(w) return w.class end,
    chrome_off = function() return false end,
    never_group = function() return false end,
    groupable = function() return true end,
    too_small = function() return false end,
    owns_workspace = function() return true end,
    dragging = function() return false end,
    drag_owns = function() return false end,
    refresh = function(w) return w end,
  }
  for k, v in pairs(over or {}) do e[k] = v end
  -- `pairs` skips nil values, so "no plugin loaded" cannot be an override of nil:
  -- it is asked for explicitly.
  if over and over.no_plugin then e.groupable = nil end
  return e
end

local win = { class = "foot" }

-- The obvious cases first: a window that is pinned, hidden, or has no class is not
-- a tab.
check("skip.pinned", grouping.skip({ class = "foot", pinned = true }, env()), true)
check("skip.hidden", grouping.skip({ class = "foot", hidden = true }, env()), true)
check("skip.nil", grouping.skip(nil, env()), true)
check("skip.empty-class", grouping.skip({ class = "" }, env()), true)
check("skip.plain", grouping.skip(win, env()), false)

-- An app with its titlebar switched off has no tabbar to put tabs in.
check("skip.chrome-off", grouping.skip(win, env({ chrome_off = function() return true end })), true)

-- Nested compositors share one class: grouping them would put every nest in one tab.
check("skip.never-group", grouping.skip(win, env({ never_group = function() return true end })), true)

-- Dialogs and the pack's own surfaces.
for _, cls in ipairs({ "org.freedesktop.portal.FileChooser", "polkit-gnome", "hyprbars-titlebar" }) do
  check("skip.dialog." .. cls, grouping.skip({ class = cls }, env()), true)
end

-- The plugin's own classification wins when it is loaded.
check("skip.plugin-refuses", grouping.skip(win, env({ groupable = function() return false end })), true)
check("skip.plugin-allows", grouping.skip(win, env()), false)

-- Without the plugin, the size floor is the fallback -- and it is *not* consulted
-- when the plugin answered.
local floor = env({ groupable = function() return true end, too_small = function() return true end })
check("skip.plugin-wins-over-floor", grouping.skip(win, floor), false)
local no_plugin = env({ no_plugin = true, too_small = function() return true end })
check("skip.floor-without-plugin", grouping.skip(win, no_plugin), true)
check("skip.floor-not-too-small", grouping.skip(win, env({ no_plugin = true })), false)

-- Already together: the same group object, not merely the same class.
local groupA, groupB = { id = "a" }, { id = "b" }
check("same.same", grouping.same_group({ group = groupA }, { group = groupA }), true)
check("same.different", grouping.same_group({ group = groupA }, { group = groupB }), false)
check("same.one-ungrouped", grouping.same_group({ group = groupA }, {}), false)
check("same.nil", grouping.same_group(nil, { group = groupA }), false)

-- The plan, in the order the branches matter.
check("plan.skip", grouping.join_plan(win, { class = "foot" }, env({ groupable = function() return false end })), "skip")
check("plan.leave", grouping.join_plan(win, { class = "foot" }, env({ owns_workspace = function() return false end })), "leave")
check("plan.none", grouping.join_plan(win, nil, env()), "none")
check("plan.same", grouping.join_plan({ class = "foot", group = groupA }, { class = "foot", group = groupA }, env()), "same")
check("plan.wait", grouping.join_plan(win, { class = "foot" }, env({
  dragging = function() return true end,
  drag_owns = function(w) return w == win end,
})), "wait")
check("plan.join", grouping.join_plan(win, { class = "foot" }, env()), "join")

-- A drag that owns neither window does not hold the join back.
check("plan.drag-elsewhere", grouping.join_plan(win, { class = "foot" }, env({
  dragging = function() return true end,
  drag_owns = function() return false end,
})), "join")

-- A window that already has a peer is not held by a drag it is not part of.
check("plan.skip-before-anything", grouping.join_plan({ class = "foot", pinned = true }, nil,
  env({ owns_workspace = function() return false end })), "skip")

-- The group is compared on refreshed handles, not on the ones that came in: a
-- window from an event and a peer from a search can both be stale. Here the search
-- result still looks ungrouped and the refreshed one is in the group.
local stale_w = { class = "foot" }
local stale_peer = { class = "foot" }
local fresh_w, fresh_peer = { class = "foot", group = groupA }, { class = "foot", group = groupA }
local refreshed = {}
check("plan.refresh-both", grouping.join_plan(stale_w, stale_peer, env({
  refresh = function(w)
    refreshed[#refreshed + 1] = w
    if w == stale_w then return fresh_w end
    if w == stale_peer then return fresh_peer end
    return w
  end,
})), "same")
check("plan.refresh-count", #refreshed, 2)
check("plan.refresh-window-first", refreshed[1], stale_w)

-- The refreshed handles are used for the group comparison only: the drag check must
-- still recognise the window it was given. Here the refresh returns strangers that
-- share no group, so the comparison says "not together", and drag_owns recognises
-- the original window -- the answer is "wait", not "join".
local marked = { class = "foot" }
local marked_peer = { class = "foot" }
check("plan.refresh-does-not-reach-drag", grouping.join_plan(marked, marked_peer, env({
  refresh = function() return { class = "foot" } end,
  dragging = function() return true end,
  drag_owns = function(w) return w == marked end,
})), "wait")

if failures > 0 then
  os.exit(1)
end
print("grouping ok")
