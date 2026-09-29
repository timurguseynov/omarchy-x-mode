#!/usr/bin/env bash
# A nested Hyprland's toplevel is class aquamarine (the wayland backend's app
# id). Same-app grouping puts every such window into one tab, and the tab that
# is not current is not drawn. These windows keep their titlebar; they are
# just never a group. A reload that finds them already grouped pulls them
# back out — that is the state an install meets.
. "$(dirname "$0")/../../lib.sh"

open_command aquamarine foot --app-id=aquamarine
open_command aquamarine foot --app-id=aquamarine
# The join retry is 200ms. Wait past it, or this can pass before they group.
settle

assert_eq "$(count_class aquamarine)" 2 "both windows exist"
assert_le "$(group_size aquamarine)" 1 "an aquamarine window must not be grouped"

# Force the group a reload would find, then reload. The load-time pass is a
# 250ms oneshot, so the check waits past that.
nest_ctl eval '
  local wins = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    local cls = string.lower(tostring(w.initial_class or w.class or ""))
    if cls == "aquamarine" then
      wins[#wins + 1] = w
    end
  end
  if #wins >= 2 then
    hl.dispatch(hl.dsp.group.toggle({ window = wins[1] }))
    local peer = hl.get_window("address:" .. tostring(wins[1].address)) or wins[1]
    if peer.group ~= nil then
      peer.group:add(wins[2])
    end
  end
' >/dev/null
settle
assert_eq "$(group_size aquamarine)" 2 "the fixture really did group them"

nest_ctl reload >/dev/null
sleep 0.4
assert_le "$(group_size aquamarine)" 1 "a reload pulls an aquamarine group apart"
