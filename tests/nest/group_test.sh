#!/usr/bin/env bash
# A same-app window joins the group. The tabbar grows the chrome upward, so the
# window has to move down by the tabbar height to keep the same visual top; a
# group whose box was not absorbed shows up as visual_top below the bar.
. "$(dirname "$0")/../lib.sh"

open_window foot
open_window foot 2

assert_eq "$(group_size foot)" 2 "the second foot joins the group"
assert_ge "$(visual_top foot)" 36 "the tabbar stays below the bar"
