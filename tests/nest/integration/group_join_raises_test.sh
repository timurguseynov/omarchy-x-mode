#!/usr/bin/env bash
# Regression: a window joining a group of its own class was added as a tab but
# the group was not raised, so the focused window ended up behind another
# floating app. The window that joins has to take focus and bring the group up.
#
# The other app is opened before the join, so there is something to be raised
# above.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
assert_eq "$(group_size foot)" 2 "two windows share the group"

open_window kitty
assert_eq "$(topmost)" kitty "the other app is on top before the join"

open_window foot 3
sleep 0.4

assert_eq "$(active_class)" foot "the joining window takes focus"
assert_eq "$(topmost)" foot "joining a group raises it above the other app"
assert_eq "$(group_size foot)" 3 "the joining window is a tab of the group"
