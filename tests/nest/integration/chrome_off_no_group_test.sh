#!/usr/bin/env bash
# Regression: a class with the chrome turned off still had its windows grouped,
# so a second window vanished into a tabbar that is not drawn. chrome off means
# no titlebar, no tabbar and no same-app grouping.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

printf '%s\n' '{"options":{},"apps":{"foot":{"chrome":false}}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

open_window foot
open_window foot 2

assert_eq "$(count_class foot)" 2 "both windows exist"
assert_le "$(group_size foot)" 1 "a chrome-off window must not be grouped"
