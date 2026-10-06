#!/usr/bin/env bash
# Regression: the panel stores an app key lowercased, but Hyprland matches a
# rule's class as a case-sensitive RE2 full match. A class with an uppercase
# letter in it -- Thunderbird's org.mozilla.Thunderbird -- therefore never
# matched, and its titlebar stayed no matter what the panel said. The rule has to
# match the class case-insensitively.
#
# This is the panel's own path: the window is already open, the panel writes the
# settings file and calls x_mode.refresh_apps_off() -- no reload. With chrome off
# the window box is what is on screen, so its top sits one inset below the bar
# (24 + gaps_out/2 + border, around 36); with chrome on it is 28 lower.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

open_command org.mozilla.Thunderbird foot --app-id=org.mozilla.Thunderbird
snap org.mozilla.Thunderbird left
read -r _ y_on _ _ _ <<<"$(win_geom org.mozilla.Thunderbird)"
assert_ge "$y_on" 60 "the titlebar is on before the panel toggle"

# What the panel writes is lowercased; the window's class keeps its capital.
printf '%s\n' '{"options":{},"apps":{"org.mozilla.thunderbird":{"chrome":false}}}' > "$SETTINGS"
refresh_apps
settle

snap org.mozilla.Thunderbird left
read -r _ y_off _ _ _ <<<"$(win_geom org.mozilla.Thunderbird)"
assert_ge "$y_off" 24 "the window stays below the bar"
assert_le "$y_off" 40 "an uppercase class reaches the bar, not the titlebar inset"
