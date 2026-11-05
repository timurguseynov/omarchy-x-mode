-- Whether a window may become a tab, and what to do with it when it may: join
-- now, wait for a drag to finish, or leave it alone. The decisions are here; the
-- calls that move windows stay in x-mode.lua.
--
-- Every branch is a rule that has cost someone a window: a pinned window pulled
-- into a tab, an app with its titlebar switched off, a nested compositor whose
-- toplevels all share one class.
local M = {}

-- Whether this window must stay a window.
-- env: class_of(w), chrome_off(cls), never_group(cls), groupable(w) (nil when the
-- plugin is not loaded), too_small(w) (the fallback used then).
function M.skip(w, env)
  if w == nil or w.pinned or w.hidden then
    return true
  end
  local cls = env.class_of(w) or ""
  if env.chrome_off ~= nil and env.chrome_off(cls) then
    return true
  end
  -- Nested compositor toplevels share one class, so same-app grouping would put
  -- every nest in one tab. The titlebar stays.
  if env.never_group ~= nil and env.never_group(cls) then
    return true
  end
  -- Dialogs and the pack's own bars: a portal prompt, a polkit prompt, a titlebar
  -- surface. An empty class is not an app.
  if cls == "" or cls:find("portal", 1, true) or cls:find("polkit", 1, true) or cls:find("titlebar", 1, true) then
    return true
  end
  -- Hyprland's own popup classification (override-redirect, modal, X11 MENU, and
  -- the like). Size is not a signal: a small document is still a document.
  if env.groupable ~= nil then
    if not env.groupable(w) then
      return true
    end
  elseif env.too_small ~= nil and env.too_small(w) then
    -- Plugin not loaded yet: the old size floor, as a last resort.
    return true
  end
  return false
end

-- Whether two windows are already in the same group. Both must be refreshed by the
-- caller -- `join_plan` does it, and this is why: a handle from a search or from an
-- event can report a group it no longer has.
function M.same_group(a, b)
  if a == nil or b == nil or a.group == nil or b.group == nil then
    return false
  end
  return a.group == b.group
end

-- What to do about a new window and its peer:
--   "skip"   it is not a tab at all
--   "leave"  the pack does not own this workspace
--   "none"   there is no peer to join
--   "same"   already in that group
--   "wait"   a drag owns either window; join when the drag ends
--   "join"   group it now
function M.join_plan(w, peer, env)
  if M.skip(w, env) then
    return "skip"
  end
  if not env.owns_workspace(w) then
    return "leave"
  end
  if peer == nil then
    return "none"
  end
  -- Both handles are refreshed for the comparison, as the config did when this was
  -- inline: the peer came out of a search and the window out of an event, and either
  -- can be stale by the time the group is compared. The refreshed ones are locals:
  -- the drag check below has to see the windows it was given, the same way the old
  -- inline code kept its own arguments and threw the refreshed handles away.
  local fresh_w, fresh_peer = w, peer
  if env.refresh ~= nil then
    fresh_w = env.refresh(w) or w
    fresh_peer = env.refresh(peer) or peer
  end
  if M.same_group(fresh_w, fresh_peer) then
    return "same"
  end
  if env.dragging() and (env.drag_owns(w) or env.drag_owns(peer)) then
    return "wait"
  end
  return "join"
end

return M
