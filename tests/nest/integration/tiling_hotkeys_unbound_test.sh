#!/usr/bin/env bash
# x-mode takes Omarchy's tiling hotkeys away: popping a window out of the tiling,
# the layout picker, and the swap/resize arrows. Pressing one must not change a
# window's geometry, group or float state.
#
# A modified keybind cannot be driven from here (see the README), so the contract
# is pinned at the bind table: if the pack binds one of these again, the geometry
# would change on a keypress the user was told is free.
. "$(dirname "$0")/../../lib.sh"

assert_ne "$(bind_count O 64)" 1 "Super+O (pop out) must not be bound"
assert_ne "$(bind_count L 64)" 1 "Super+L (layout picker) must not be bound"
assert_ne "$(bind_count T 64)" 1 "Super+T (toggle tiling) must not be bound"

# The bind list has to be readable at all, or the assertions above prove nothing.
assert_ge "$(nest_ctl binds -j | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')" 5 \
  "the nest should have the pack's binds registered"
