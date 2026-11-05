-- Choosing the window a new one joins. The rule is the pack's, the windows come
-- from the compositor, so the accessors arrive as `env` and the choice itself is
-- testable with a fake list (tests/unit/peers_test.lua).
--
-- Two shapes, on purpose:
--   find    the peer to join: an existing group of the same app wins over a bare
--           window, so a second window joins the tab it belongs to instead of
--           starting a new group.
--   exists  whether any window of the same app is there at all. `window.open_early`
--           only needs that answer, and it is asked while the window is being
--           mapped -- refreshing candidates and looking into their groups is work
--           the caller never uses.
local M = {}

-- env: class(w), ws(w), skip(w), refresh(w). `refresh` is only called for a
-- candidate that already matched, which is what the event loop did inline.
function M.find(w, windows, env)
  local class = env.class(w)
  local wid = env.ws(w)
  local fallback = nil
  for _, other in ipairs(windows) do
    if other.address ~= w.address and env.class(other) == class and env.ws(other) == wid and not env.skip(other) then
      local peer = env.refresh(other)
      if peer ~= nil and peer.group ~= nil then
        -- Prefer an existing group so a new window joins it instead of creating
        -- yet another group of the same app.
        local current = peer.group.current
        return env.refresh(current) or peer
      end
      if fallback == nil then
        fallback = peer
      end
    end
  end
  return fallback
end

-- The same match, without the group preference and without refreshing anything:
-- the answer is only "is there one", and the caller is mapping a window.
--
-- The window itself is checked first, as find_peer's entry does: a window that
-- cannot be a tab at all -- hidden, pinned, excluded by settings, not groupable --
-- is not "waiting for a peer" whatever is next to it. Skipping that check left such
-- a window hidden behind an opacity of zero whenever a candidate happened to exist.
function M.exists(w, windows, env)
  if env.skip(w) then
    return false
  end
  local class = env.class(w)
  local wid = env.ws(w)
  for _, other in ipairs(windows) do
    if other.address ~= w.address and env.class(other) == class and env.ws(other) == wid and not env.skip(other) then
      return true
    end
  end
  return false
end

return M
