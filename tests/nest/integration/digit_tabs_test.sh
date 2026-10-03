#!/usr/bin/env bash
# Cmd+1..0 are the pack's own keys, and only an app flag claims them.
#
# With the workspaces on F1..F10 Omarchy's digit binds are released and the pack
# binds the digits itself, so the key can be decided at press time by the focused
# window's class:
#
#   * the card's "reserve" switch  -> the pack's tab, and the key is eaten even
#     when there is no such tab (reserved means the app does not see it);
#   * else, "Super works as Ctrl"  -> Ctrl+digit to the app;
#   * else                         -> not ours: passed through.
#
# Nothing is on by default: a fresh system switches no tab on a digit. Omarchy's
# own digit binds are written by keycode, so the nest plants one (the 3 key) the
# way Omarchy writes it; while it is still Omarchy's, the pack must not act.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

open_window foot
open_window foot 2
open_window foot 3
assert_eq "$(group_size foot)" 3 "three windows share the group"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
assert_eq "$(active_tab_index foot)" 0 "the first tab is current to begin with"

# Off: the digit belongs to Omarchy's workspace keys.
key super+3
sleep 0.4
assert_eq "$(active_tab_index foot)" 0 "Cmd+3 leaves the tabs alone while the workspace key owns it"

# On, with nothing ticked: the pack owns the digit, but no flag claims it, so it
# must not switch a tab on its own.
printf '%s\n' '{"options":{"workspacesOnFkeys":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
wait_until 5 [ "$(bind_count 3 64)" = 1 ] || fail "the digit did not become the pack's after the reload"

key super+3
sleep 0.4
assert_eq "$(active_tab_index foot)" 0 "with nothing ticked Cmd+3 switches nothing"

# The reserve switch: the digit is the pack's tab, eaten by it.
printf '%s\n' '{"options":{"workspacesOnFkeys":true},"apps":{"foot":{"digitTabs":true}}}' > "$SETTINGS"
refresh_apps
sleep 0.4
key super+3
wait_until 3 [ "$(active_tab_index foot)" = 2 ] || fail "Cmd+3 did not switch to the third tab"
assert_eq "$(active_tab_index foot)" 2 "a reserved Cmd+3 switches the pack's tab"

# Cmd+0 is the tenth tab, so ten of them have to exist.
for n in 4 5 6 7 8 9 10; do
  open_window foot "$n"
done
wait_until 5 [ "$(group_size foot)" = 10 ] || fail "the windows did not join one group of ten"
key super+0
wait_until 3 [ "$(active_tab_index foot)" = 9 ] || fail "Cmd+0 did not switch to the tenth tab"
assert_eq "$(active_tab_index foot)" 9 "Cmd+0 switches to the tenth tab"

# "Super works as Ctrl" alone: the digit goes to the app as Ctrl+digit, and the
# tab stays where it is.
printf '%s\n' '{"options":{"workspacesOnFkeys":true},"apps":{"foot":{"ctrlAsSuper":true}}}' > "$SETTINGS"
refresh_apps
sleep 0.4
key super+5
sleep 0.4
assert_eq "$(active_tab_index foot)" 9 "Ctrl-works-as-Ctrl does not switch a tab"

# And what the app is handed is the chord itself, not merely something that is not
# a tab switch: one window is given a physical Ctrl+5, another the digit, and the
# bytes have to match. A capture that has already been written to cannot be
# reused -- the `cat` keeps the file it opened -- so each measurement gets a
# window of its own. `stty raw -echo` keeps the pty from editing the line.
CAPA="$NEST_STATE/digit-tabs-a.out"
CAPB="$NEST_STATE/digit-tabs-b.out"
CAPC="$NEST_STATE/digit-tabs-c.out"
received() { od -An -v -tx1 "$1" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//'; }
rm -f "$CAPA" "$CAPB" "$CAPC"

open_command footcapa foot -a footcapa sh -c "stty raw -echo; cat > '$CAPA'"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:footcapa' })" >/dev/null
sleep 0.3
key ctrl+5
sleep 0.5
base="$(received "$CAPA")"
assert_ne "$base" "" "a physical Ctrl+5 hands the terminal something"

printf '%s\n' '{"options":{"workspacesOnFkeys":true},"apps":{"foot":{"ctrlAsSuper":true},"footcapb":{"ctrlAsSuper":true}}}' > "$SETTINGS"
refresh_apps
sleep 0.4
open_command footcapb foot -a footcapb sh -c "stty raw -echo; cat > '$CAPB'"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:footcapb' })" >/dev/null
sleep 0.3
key super+5
sleep 0.5
assert_eq "$(received "$CAPB")" "$base" "Cmd+5 hands the app the bytes Ctrl+5 does"

# Both flags on one app: the reservation is the more specific rule on the digit,
# so it wins -- the tab moves, and the app is handed nothing.
printf '%s\n' '{"options":{"workspacesOnFkeys":true},"apps":{"foot":{"ctrlAsSuper":true,"digitTabs":true}}}' > "$SETTINGS"
refresh_apps
sleep 0.4
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
key super+6
wait_until 3 [ "$(active_tab_index foot)" = 5 ] || fail "with both flags Cmd+6 did not switch the tab"
assert_eq "$(active_tab_index foot)" 5 "both flags on: the reservation wins and the tab moves"

# Reserved but there is no such tab: the key is eaten, so an app that would have
# taken Ctrl+2 through its other flag is handed nothing at all.
printf '%s\n' '{"options":{"workspacesOnFkeys":true},"apps":{"foot":{"ctrlAsSuper":true},"footcapc":{"ctrlAsSuper":true,"digitTabs":true}}}' > "$SETTINGS"
refresh_apps
sleep 0.4
open_command footcapc foot -a footcapc sh -c "stty raw -echo; cat > '$CAPC'"
wait_until 3 [ -e "$CAPC" ] || fail "the capture window did not open its file"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:footcapc' })" >/dev/null
sleep 0.3
key super+2
sleep 0.5
assert_eq "$(received "$CAPC")" "" "a reserved digit with no tab hands the app nothing"
