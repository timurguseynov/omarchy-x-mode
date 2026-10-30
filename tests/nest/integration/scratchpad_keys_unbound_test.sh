#!/usr/bin/env bash
# Cmd+S toggles the scratchpad and Cmd+Alt+S moves the focused window into it.
# x-mode drops both so the keys reach the app. The nest plants those binds
# before the pack loads; afterwards neither may remain.
. "$(dirname "$0")/../../lib.sh"

# The nest's settings file is shared by every scenario that runs in this slot, and
# a scenario before this one may have left Super as Ctrl on -- which binds Super+S
# on purpose, so the key really is bound and this check would read as a bug. Start
# from the shape this scenario is about.
printf '%s\n' '{"options":{},"apps":{}}' > "$NEST_SETTINGS"
nest_ctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null
wait_until 8 '[ "$(bind_count_desc x-mode-super-ctrl 64)" = 0 ]' || fail "Super as Ctrl is still planned"

assert_eq "$(bind_count S 64)" 0 "Super+S must not be bound"
assert_eq "$(bind_count S 72)" 0 "Super+Alt+S must not be bound"
