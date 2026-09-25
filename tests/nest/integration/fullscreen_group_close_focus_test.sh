#!/usr/bin/env bash
# Closing the current tab of a group that sits under a fullscreen window must not
# steal the focus back into the group. keepGroupFocusOnClose raises the next tab
# and then focuses it; the raise is held under the fullscreen window, and the
# rawWindowFocus after it skips the fullscreen guard, so it used to focus the
# invisible, input-blocked tab anyway.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
assert_eq "$(group_size foot)" 2 "two windows share the group"

open_window kitty
nest_ctl dispatch "hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set', window = 'class:kitty' })" >/dev/null
sleep 0.3
assert_eq "$(active_class)" kitty "the fullscreen window has the focus"

# Close the group's current tab, the way the app itself would. Pick the target
# first: closing inside the loop would make the remaining tab the current one and
# the loop would close it too.
nest_ctl eval "local target = nil
for _,w in ipairs(hl.get_windows()) do
  if w.class == 'foot' and w.group then
    local c = w.group.current
    if c and c.address == w.address then target = w end
  end
end
if target then hl.dispatch(hl.dsp.window.close({ window = target })) end" >/dev/null
sleep 0.6

assert_eq "$(group_size foot)" 1 "one foot tab is left"
assert_eq "$(active_class)" kitty "closing a tab under fullscreen must not steal the focus"
