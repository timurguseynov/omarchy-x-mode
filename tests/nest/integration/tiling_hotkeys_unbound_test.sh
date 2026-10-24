#!/usr/bin/env bash
# The tiling hotkeys are the pack's only on its own workspaces. It binds them
# (popping a window out, the layout toggles, the swap/resize arrows), and on an
# xmode workspace they hand the key to the app instead of tiling it; on every
# other mode they do what Omarchy binds -- see xmode_mode_test for that half.
#
# What is pinned here is that the pack did not go back to leaving a *duplicate*
# behind and that a press changes nothing on an xmode workspace: exactly one bind
# per key, and a window that is still floating and not pinned afterwards.
. "$(dirname "$0")/../../lib.sh"

# Pop-out and the float toggle are the two whose effect is visible on the window
# itself, so they are pressed as well as counted.
assert_eq "$(bind_count_desc "Pop window out" 64)" 1 "Super+O is bound once, by the pack"
assert_eq "$(bind_count_desc "Toggle window floating" 64)" 1 "Super+T is bound once, by the pack"
assert_eq "$(bind_count_desc "Cycle workspace layout" 64)" 1 "Super+L is the pack's layout cycle, bound once"

state() { # CLASS FIELD -> what the nest says about the first window of the class
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c['mapped'] and not c['hidden']:
        print('yes' if c['$2'] else 'no')
        break"
}

open_window foot
settle
assert_eq "$(state foot floating)" yes "the nest is in xmode, so the window floats"

key super+o
sleep 0.4
assert_eq "$(state foot pinned)" no "Super+O on an xmode workspace does not pop the window out"
assert_eq "$(state foot floating)" yes "and does not unfloat it"

key super+t
sleep 0.4
assert_eq "$(state foot floating)" yes "Super+T on an xmode workspace leaves it floating"

# The bind list has to be readable at all, or the assertions above prove nothing.
assert_ge "$(nest_ctl binds -j | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')" 5 \
  "the nest should have the pack's binds registered"
