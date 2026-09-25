#!/usr/bin/env bash
# Cmd+S toggles the scratchpad and Cmd+Alt+S moves the focused window into it.
# x-mode drops both so the keys reach the app. The nest plants those binds
# before the pack loads; afterwards neither may remain.
. "$(dirname "$0")/../../lib.sh"

assert_eq "$(bind_count S 64)" 0 "Super+S must not be bound"
assert_eq "$(bind_count S 72)" 0 "Super+Alt+S must not be bound"
