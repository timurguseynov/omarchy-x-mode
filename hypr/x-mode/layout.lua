-- omarchy-x-mode: everything that puts a window on a zone.
--
-- Geometry is not here. hyprbars/snap.cpp owns the zones, the snap cycle, the
-- work frame and the chrome (Snap::), and this asks it -- snap, zone, cycle,
-- usable, chrome_height -- and remembers what it asked for. There is no second
-- copy of a zone in Lua, and no path in Lua that moves a window without asking
-- the plugin first: a missing plugin makes a pass empty, never a fallback box.
--
-- Alignment is applied, never scheduled. A pass that cannot run yet -- the
-- plugin is loaded from exec_on_start, so it does not exist on the first parse,
-- and the dock's width arrives after it -- is kept in `pending` and run by one
-- poll the moment the plugin can answer. Nothing here waits a fixed time for
-- geometry to appear, and nothing silently drops a pass because the geometry
-- was not there.
--
-- The pure half is at the top and takes plain tables, so tests/unit can run it
-- with no compositor: plan_arrange is the whole decision an arrange makes. The
-- rest works off the `ctx` table x-mode.lua hands to init(), and owns the two
-- pieces of state alignment needs across events: the frame the plugin resolves
-- (bars and dock), and the one-shot arrange (its marker, its fade, its shuffle).

local M = {}

-- ------------------------------------------------------------------- pure --

-- Which side each window goes to when an arrange deals them: one window per
-- class per workspace (the same app is one group -- consolidate() has already
-- folded it -- and a second window of it on one space would land on the other
-- half and then be yanked back into the group), each space dealt on its own so a
-- window never changes workspace.
--
-- A space with a single group has nothing to be on a side of, so it is centred --
-- the plugin's almost-maximize box, the same one `Super+Alt+A` gives -- and only
-- from the second group on do the sides alternate, so a workspace with two or
-- more groups fills left and right.
--
-- `windows` is a list of { key = <anything>, class = <class>, space = <space> },
-- `shuffle(n)` returns 1..n and belongs to the caller so a test can deal in a
-- fixed order. Returns a list of { key = <the same key>, kind = <snap kind> }.
function M.plan_arrange(windows, shuffle)
  local seen, by_space, spaces = {}, {}, {}
  for _, w in ipairs(windows) do
    local cls = tostring(w.class or "")
    local space = tostring(w.space or "")
    local key = cls .. "@" .. space
    if cls ~= "" and not seen[key] then
      seen[key] = true
      if by_space[space] == nil then
        by_space[space] = {}
        spaces[#spaces + 1] = space
      end
      by_space[space][#by_space[space] + 1] = w
    end
  end

  local out = {}
  for _, space in ipairs(spaces) do
    local leaders = by_space[space]
    if #leaders == 1 then
      out[#out + 1] = { key = leaders[1].key, kind = "almost-maximize" }
    else
      -- Fisher-Yates, so each space is split roughly evenly; without it the order
      -- is just whatever Hyprland enumerated.
      for i = #leaders, 2, -1 do
        local j = shuffle(i)
        leaders[i], leaders[j] = leaders[j], leaders[i]
      end
      for i, w in ipairs(leaders) do
        out[#out + 1] = { key = w.key, kind = (i % 2 == 1) and "left" or "right" }
      end
    end
  end
  return out
end

-- -------------------------------------------------------------------- ctx --

local ctx = nil

function M.init(c)
  ctx = c
end

local function plugin()
  return ctx.plugin()
end

local function windows()
  return ctx.list()
end

-- Either fullscreen flag. A client-fullscreen window (a video player, a game)
-- keeps the compositor's flag clear, and moving it would break it out of the
-- mode its own choice put it in.
local function fullscreen(w)
  if w == nil then
    return false
  end
  return (w.fullscreen ~= nil and w.fullscreen ~= 0) or (w.fullscreen_client ~= nil and w.fullscreen_client ~= 0)
end

local function vec(value)
  if type(value) ~= "table" then
    return 0, 0
  end
  if value.x ~= nil then
    return value.x, value.y or 0
  end
  if value.w ~= nil then
    return value.w, value.h or 0
  end
  return value[1] or 0, value[2] or 0
end

-- The work frame: the monitor minus its reserved area and the dock inset, with
-- the same bar-height memory across a shell restart a snap uses. It is the
-- frame a left and a right half split, so a restore default taken from it can
-- never disagree with the zones. Nil when the plugin is not there: there is no
-- frame to take, and the caller decides what that means for it.
function M.usable(monitor)
  local p = plugin()
  if p == nil or p.usable == nil or monitor == nil then
    return nil
  end
  local ok, box = pcall(p.usable, monitor.name)
  if not ok or type(box) ~= "table" then
    return nil
  end
  return box.x, box.y, box.w, box.h
end

-- The chrome above a window's content. The plugin's number, including its
-- no_bar check (Snap::chromeH): a window with its titlebar off has no chrome to
-- keep free above its content.
function M.chrome_h(window)
  local p = plugin()
  if p == nil or p.chrome_height == nil then
    return 0
  end
  local ok, h = pcall(p.chrome_height, window)
  if not ok or type(h) ~= "number" then
    return 0
  end
  return h
end

-- ------------------------------------------------------- apply what we ask --

-- The three ways a window is put on a zone: the snap itself, the restore of the
-- box it had before, and the step through a side's cycle sizes. Geometry is the
-- plugin's in all three, including the client minimum a zone grows to
-- (Snap::applyKind / contentBox), so a snap to a zone too small for the client
-- stays the plugin's decision and not a second rule in here.

local saved = {}

-- The frame -- the pack's three numbers plus the bar top the plugin resolves --
-- and the frame the windows were last placed in. Every apply and the queue's gate
-- use both, and they are defined with the rest of the frame further down: these
-- forward names are what keeps an apply from reaching a global that never exists.
-- A timer callback that throws is caught and logged by Hyprland, and the pass it
-- was going to run then never runs at all -- silently, which is how this looked.
local frame_of
local applied_frame = nil

-- The restore points outlive the parse. They have to: a reload (a theme switch,
-- the panel's toggles, an install) recreates the Lua state but not the windows,
-- so a point kept in memory alone turned Ctrl+Alt+Down into "give me the default
-- box" after every reload. One line per window in the state dir, keyed by the
-- address, which is stable for the session.
local function restore_path()
  if ctx.state_dir == nil then
    return nil
  end
  return ctx.state_dir .. "/restore.txt"
end

local function write_saved()
  local path = restore_path()
  if path == nil then
    return
  end
  local file = io.open(path, "w")
  if file == nil then
    return
  end
  for addr, box in pairs(saved) do
    -- math.floor: the addresses and sizes come from Hyprland as floats, and %d
    -- on a number that is not integer-valued raises in Lua 5.3+.
    file:write(string.format(
      "%s %d %d %d %d\n",
      tostring(addr), math.floor(box.x), math.floor(box.y), math.floor(box.w), math.floor(box.h)
    ))
  end
  file:close()
end

-- Read back what earlier parses saved. An entry whose window is gone is dropped
-- on the way in: Hyprland reuses window addresses, and a new window must not
-- inherit a closed one's box. The file is rewritten, so the drop sticks.
function M.load_restore()
  local path = restore_path()
  if path == nil then
    return
  end
  local file = io.open(path, "r")
  if file == nil then
    return
  end
  local live = {}
  for line in file:lines() do
    local addr, x, y, w, h = line:match("^(%S+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)$")
    if addr ~= nil and ctx.window_at(addr) ~= nil then
      live[addr] = { x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) }
    end
  end
  file:close()
  saved = live
  write_saved()
end

-- Remember the box a window had, so a later restore (or a snap after a drag) can
-- go back to it. The drag event calls this when the gesture starts.
function M.save(window)
  if window == nil then
    return
  end
  local x, y = vec(window.at)
  local w, h = vec(window.size)
  saved[window.address] = { x = x, y = y, w = w, h = h }
  write_saved()
end

-- A closed window's box is not a restore point for anything: drop it, so a later
-- window at the same address cannot inherit it.
function M.forget(window)
  if window == nil or window.address == nil then
    return
  end
  if saved[window.address] ~= nil then
    saved[window.address] = nil
    write_saved()
  end
end

local function place(x, y, w, h, window)
  window = window or hl.get_active_window()
  if window == nil then
    return
  end

  if window.fullscreen and window.fullscreen ~= 0 then
    hl.dispatch(hl.dsp.window.fullscreen({ action = "unset", window = window }))
  end
  if not window.floating then
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = window }))
  end

  hl.dispatch(hl.dsp.window.resize({ x = w, y = h, relative = false, window = window }))
  hl.dispatch(hl.dsp.window.move({ x = x, y = y, relative = false, window = window }))
end

function M.snap(kind, window)
  window = window or hl.get_active_window()
  if window == nil then
    return
  end

  if kind ~= "restore" then
    M.save(window)
  end

  if kind == "restore" then
    local monitor = window.monitor or hl.get_monitor_at_cursor() or hl.get_active_monitor()
    if monitor == nil then
      return
    end
    local x, y, w, h = M.usable(monitor)
    if x == nil then
      return
    end
    local prev = saved[window.address]
    if prev then
      place(prev.x, prev.y, prev.w, prev.h, window)
    else
      place(x + math.floor(w * 0.15), y + math.floor(h * 0.12), math.floor(w * 0.7), math.floor(h * 0.76), window)
    end
    return
  end

  -- Join an existing same-app group first; only create a fresh group if there
  -- is no group to join (otherwise snapping would spawn a second group). Join
  -- directly (no keep_pos) so the snapped position is not undone afterwards.
  if window.group == nil then
    local peer = ctx.find_peer(window)
    if peer ~= nil and peer.group ~= nil then
      pcall(function()
        peer.group:add(window)
      end)
    end
  end

  local p = plugin()
  if p ~= nil and p.snap ~= nil then
    pcall(function()
      p.snap({ kind = kind, window = window })
    end)
  end
  applied_frame = frame_of()
end

-- Super+Alt+Left/Right: step through the side's cycle sizes (half, two thirds, a
-- third) and, when the window is not on one of them yet, snap it to the side's
-- zone. Both the sizes and the matching are the plugin's (Snap::cycle) -- the
-- same frame, chrome, client minimum and insets a zone is built from -- so there
-- is no second copy to keep in step.
function M.cycle(side)
  local window = hl.get_active_window()
  local monitor = hl.get_monitor_at_cursor() or hl.get_active_monitor()
  if window == nil or monitor == nil then
    return
  end

  local p = plugin()
  if p ~= nil and p.cycle ~= nil then
    local ok, stepped = pcall(p.cycle, window, side)
    if ok and stepped then
      -- The step *is* an apply: it moved the window onto a cycle size, so the
      -- frame it was placed in has to be remembered here too (a shell restart can
      -- take the bar away between this and the next snap).
      applied_frame = frame_of()
      return
    end
  end
  M.snap(side, window)
end

-- ----------------------------------------------------- the alignment queue --

-- Everything that asks the plugin for geometry runs through here. A pass whose
-- plugin is not there yet is *kept*, not dropped: that state is normal, not an
-- error (the config parses before the plugin exists, and the plugin's own load
-- re-runs this file). The poll below runs whatever is left the moment the plugin
-- can answer, and stops as soon as there is nothing left. Without the plugin
-- there is no geometry to align to at all, so a pass still waiting after five
-- seconds is dropped -- the next load asks again.
local ALIGN_GIVE_UP_TICKS = 50
local ALIGN_TICK_MS = 100
local pending = {}
local timer = nil
local missing = 0
local blocked_ticks = 0

local function ready()
  local p = plugin()
  return p ~= nil and p.snap ~= nil and p.zone ~= nil
end

local function flush()
  if not ready() then
    missing = missing + 1
    if missing > ALIGN_GIVE_UP_TICKS then
      pending = {}
      missing = 0
      if timer ~= nil then
        timer:set_enabled(false)
      end
    end
    return
  end
  missing = 0
  -- A frame whose bar top is unknown (the bar is gone and the plugin has nothing
  -- remembered) is a frame of the whole screen: placing windows against it puts
  -- them at the top edge, and the bar coming back would have to move them again.
  -- So the pass waits for the bar -- but only so long. A desktop that really has
  -- no bar has top 0 for good, and there the pass has to run; and if the bar
  -- comes back after this wait, the frame change re-applies what was placed.
  if not frame_of().known then
    blocked_ticks = blocked_ticks + 1
    if blocked_ticks <= ALIGN_GIVE_UP_TICKS then
      return
    end
  end
  blocked_ticks = 0
  -- A drag owns the box it is moving; re-applying a zone under it would fight
  -- the gesture. The pass stays pending until the drag ends (the drag event
  -- flushes) or the next tick sees it gone.
  if ctx.dragging() then
    return
  end
  local todo = pending
  pending = {}
  for _, fn in pairs(todo) do
    pcall(fn)
  end
  if next(pending) == nil and timer ~= nil then
    timer:set_enabled(false)
  end
end

local function arm()
  if timer == nil then
    timer = hl.timer(flush, { timeout = ALIGN_TICK_MS, type = "repeat" })
  else
    timer:set_enabled(true)
  end
end

local function later(name, fn)
  pending[name] = fn
  arm()
end

-- Ask again now, without waiting for the next tick: the drag event uses this so
-- a pass held back by the gesture runs the moment the gesture is over.
function M.flush()
  flush()
end

-- ---------------------------------------------------------------- the frame --

-- The frame the zones are built from: the pack's three numbers (the outer gap,
-- the border, the dock inset) and the bar top the plugin resolves. The pack owns
-- the first three -- it publishes them in its config -- and the plugin owns the
-- top, which is why the frame is *asked for*, never cached: a shell restart
-- takes the bar away for a moment and brings it back, and both moments move
-- every zone.
--
-- `known` is the other half: the top is 0 both for "the bar is gone" and for "the
-- bar was never seen", and a pass that places windows may not do it against a
-- frame that is really the whole screen when a bar is expected. Live top, or a
-- top the plugin still remembers, is the difference. A plugin too old to answer
-- is taken as known.
frame_of = function()
  local f = { gap = ctx.gap_out(), border = ctx.border(), inset = ctx.dock_pull(), top = 0, known = true }
  local p = plugin()
  if p == nil or p.bar_top == nil then
    return f
  end
  local ok, top, live = pcall(p.bar_top)
  if not ok or type(top) ~= "number" then
    return f
  end
  f.top = top
  f.known = top > 0 or (type(live) == "number" and live > 0)
  return f
end

local function same_frame(a, b)
  return a.gap == b.gap and a.border == b.border and a.inset == b.inset and a.top == b.top
end

-- The frame the windows that are on a zone were last placed in. It is set by
-- every apply (a snap, the arrange, a re-apply), and a frame that has moved
-- since is what asks for those windows to be placed again. (Declared with the
-- other forward names, because an apply sets it before this point in the file.)

-- Put every window that is still on a zone back on that zone, matched against
-- the frame the window was placed in. That is the load-time re-apply for a frame
-- that moved instead of a config that reloaded: a right half stays the right
-- half when the dock card changes width, and a window put at the top edge while
-- the bar was away comes back under the bar when the bar returns. The plugin
-- matches against the old frame (the overrides), so a window the user moved --
-- it no longer sits on a zone -- is left exactly where it is.
local function reapply(old)
  local p = plugin()
  if p == nil or p.zone == nil then
    return
  end
  for _, w in ipairs(windows()) do
    if w.floating and not w.pinned and not w.hidden then
      local ok, kind = pcall(p.zone, w, old)
      if not ok or type(kind) ~= "string" or kind == "" then
        local ok2, kind2 = pcall(p.zone, w)
        kind = ok2 and kind2 or nil
      end
      if type(kind) == "string" and kind ~= "" then
        pcall(function()
          p.snap({ kind = kind, window = w })
        end)
      end
    end
  end
  applied_frame = frame_of()
end

-- The frame moved: re-apply what the old one held. Nothing to do when the
-- numbers are the same, so an event that fires without a change (a reload that
-- finds the same card, a layer opening that is not the bar) does not move
-- anything.
function M.frame_changed()
  if applied_frame == nil then
    return
  end
  local now = frame_of()
  if same_frame(applied_frame, now) then
    return
  end
  local old = applied_frame
  applied_frame = now
  later("frame", function()
    reapply(old)
  end)
end

-- ------------------------------------------------------------------- gaps --

-- A window can be sitting in one of two layouts: the one the live gaps make, or
-- the one "No gaps" leaves behind. Only the second is known from the option: a
-- reload starts Lua over, and the config above this file has already put the
-- normal gaps back while the windows are still where the previous option left
-- them. So each window is matched twice, once against the live gaps and, for
-- whatever is left, against the no-gap layout. Only a window in the *other*
-- layout is returned; one already in the target layout is left alone, as is a
-- window that fills no zone at all (moved by hand).
--
-- The dock inset follows gaps_out, so the no-gap pass has to push the inset that
-- layout used as well: the plugin's gap override covers the gap and the border,
-- and without this a right-edge window misses by half a gap.
function M.zoned_hits(target)
  local hits = {}
  local p = plugin()
  if p == nil or p.snap == nil or p.zone == nil then
    return hits
  end

  local rest = {}
  for _, w in ipairs(windows()) do
    if w.floating and not w.pinned and not w.hidden then
      local ok, kind = pcall(p.zone, w)
      if ok and type(kind) == "string" and kind ~= "" then
        if target ~= "live" then
          hits[#hits + 1] = { window = w, kind = kind }
        end
      else
        rest[#rest + 1] = w
      end
    end
  end

  if #rest > 0 then
    -- No gaps means gaps_out is 0, so the inset is the dock card alone.
    hl.config({ plugin = { hyprbars = { x_mode_dock_inset = ctx.dock_card() } } })
    for _, w in ipairs(rest) do
      local ok, kind = pcall(p.zone, w, { gap = 0, border = 1 })
      if ok and type(kind) == "string" and kind ~= "" and target ~= "no-gap" then
        hits[#hits + 1] = { window = w, kind = kind }
      end
    end
  end

  return hits
end

function M.apply_hits(hits)
  local p = plugin()
  if p == nil or p.snap == nil then
    return
  end
  for _, hit in ipairs(hits) do
    pcall(function()
      p.snap({ kind = hit.kind, window = hit.window })
    end)
  end
  applied_frame = frame_of()
end

-- Put the windows that are still shaped like a zone back on that zone, with the
-- live gaps. A window snapped and then nudged a little (or left a titlebar lower
-- while its client settled) is still that zone -- the plugin's zone match reads a
-- full-height zone by x and size, not by an exact y -- so a load re-applies the
-- zone box instead of leaving it out of line with the gaps around it.
--
-- This is a *load-time* pass on purpose. The same re-apply used to fall out of
-- Snap::clampToWorkArea, which runs from the bar's updateRules, and Hyprland
-- re-evaluates every window's rules whenever *any* window opens: a snapped
-- window dragged a little down flew back into its snap when another window
-- opened, with nothing in sight to explain it. A window moved out of the zone's
-- shape (another x or width) is free and is left alone, as is one being dragged
-- right now.
function M.resnap()
  later("resnap", function()
    local p = plugin()
    if p == nil or p.snap == nil or p.zone == nil then
      return
    end
    for _, w in ipairs(windows()) do
      if w.floating and not w.pinned and not w.hidden then
        local ok, kind = pcall(p.zone, w)
        if ok and type(kind) == "string" and kind ~= "" then
          pcall(function()
            p.snap({ kind = kind, window = w })
          end)
        end
      end
    end
    applied_frame = frame_of()
  end)
end

-- ----------------------------------------------------------------- arrange --

-- The one-shot deal install.sh and the on-switch ask for, behind a fade. The
-- marker is read, not taken: it is removed only once the windows have actually
-- been dealt, so a parse that cannot run the deal (no plugin yet) keeps it
-- instead of dropping the arrange on the floor. The deal itself waits in the
-- queue; the reveal has a deadline, so an answer that never comes cannot leave
-- a desktop dimmed.

local FADE_STEPS = 10
local FADE_STEP_MS = 25
local SETTLE_MS = 120
local ARRANGE_REVEAL_MS = 2000

local arrange_fade = {}
local arrange_revealed = false

local function set_window_opacity(list, value)
  for _, w in ipairs(list) do
    if w ~= nil then
      pcall(function()
        -- Hyprland draws the focused window from "opacity" and every other one
        -- from "opacity_inactive" (Window.cpp: alpha() vs alphaInactive()), so
        -- both have to be set or only the focused window is seen to change.
        hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = value, window = w }))
        hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity_inactive", value = value, window = w }))
      end)
    end
  end
end

local function reveal()
  if arrange_revealed then
    return
  end
  arrange_revealed = true
  set_window_opacity(arrange_fade, "1")
  arrange_fade = {}
end

-- Fade the windows out and leave them invisible; the poll reveals them once the
-- deal has landed. Every step is pcall'd: a window can close mid-fade, and one
-- bad handle must not leave the rest stuck at opacity 0.
local function fade_out(list)
  if #list == 0 then
    return
  end
  local step = 0
  local fade_timer
  fade_timer = hl.timer(function()
    step = step + 1
    set_window_opacity(list, string.format("%.3f", math.max(0, 1 - step / FADE_STEPS)))
    if step >= FADE_STEPS then
      fade_timer:set_enabled(false)
    end
  end, { timeout = FADE_STEP_MS, type = "repeat" })
end

-- The windows an arrange can touch, named when the fade starts so the reveal
-- targets the same set even after consolidate() folds same-app windows into a
-- group.
local function arrange_candidates()
  local out = {}
  for _, w in ipairs(windows()) do
    w = ctx.refresh(w) or w
    if w.mapped and not w.hidden and not fullscreen(w) and w.monitor ~= nil then
      out[#out + 1] = w
    end
  end
  return out
end

local function read_marker()
  if ctx.state_dir == nil then
    return false
  end
  local file = io.open(ctx.state_dir .. "/arrange", "r")
  if file == nil then
    return false
  end
  file:close()
  return true
end

local function clear_marker()
  if ctx.state_dir ~= nil then
    os.remove(ctx.state_dir .. "/arrange")
  end
end

-- Float anything still tiled. A 300ms timer does this normally; with an arrange
-- pending it is deferred to inside the fade, so the float happens on invisible
-- windows instead of moving them on screen before the fade.
function M.float_tiled()
  for _, w in ipairs(windows()) do
    if w.mapped and not w.floating and not fullscreen(w) then
      hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))
    end
  end
end

-- Deal the open windows across the workspace: a lone group centred, two or more
-- alternating left and right. The decision is the pure plan_arrange; this only
-- collects what it needs and applies what it returns.
function M.arrange()
  local entries = {}
  for _, w in ipairs(windows()) do
    w = ctx.refresh(w) or w
    if w.mapped and not w.hidden and not fullscreen(w) and w.monitor ~= nil then
      entries[#entries + 1] = { key = w, class = ctx.class_of(w), space = ctx.space_of(w) }
    end
  end
  for _, deal in ipairs(M.plan_arrange(entries, math.random)) do
    M.snap(deal.kind, deal.key)
  end
end

-- A reload in the middle of a fade leaves the windows wherever the last step put
-- them: the timers that would have faded them back die with the config, and 0.9
-- -- the first step -- is exactly what a window looks like when that happens. A
-- reinstall reloads, so that is the shape a stuck desktop has. The state the pack
-- wants is the catch-all rule's 1.0, so put it back on every window before
-- anything else touches opacity. Called once, at the top of the config.
function M.clear_fade()
  local list = {}
  for _, w in ipairs(windows()) do
    list[#list + 1] = w
  end
  set_window_opacity(list, "1")
end

-- Read the arrange request and start the fade. True when one is waiting.
function M.arrange_pending()
  if not read_marker() then
    return false
  end
  math.randomseed(os.time())
  arrange_revealed = false
  arrange_fade = arrange_candidates()
  fade_out(arrange_fade)
  return true
end

-- The load's alignment tick. With an arrange waiting: re-float and group behind
-- the fade (neither is the plugin's), then queue the deal, which needs the
-- plugin, and set the reveal deadline. Without one: just gather same-app windows.
function M.settle(arranging)
  if not arranging then
    ctx.consolidate()
    return
  end
  M.float_tiled()
  ctx.consolidate()
  later("arrange", function()
    M.arrange()
    clear_marker()
    hl.timer(reveal, { timeout = SETTLE_MS, type = "oneshot" })
  end)
  hl.timer(reveal, { timeout = ARRANGE_REVEAL_MS, type = "oneshot" })
end

-- What the alignment state is, for a stuck desktop and for tests. The pack
-- itself never reads it: everything here goes through the plugin.
function M.state()
  local copy = {}
  for addr, box in pairs(saved) do
    copy[addr] = box
  end
  return {
    saved = copy,
    frame = frame_of(),
    applied = applied_frame,
    pending = next(pending) ~= nil,
  }
end

return M
