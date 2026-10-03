#!/usr/bin/env bash
# A pinned app comes before the running ones, so with kitty pinned the first icon
# is kitty even though foot sorts before it alphabetically.
#
# The order is read off the dock's own report (`omarchy-x-mode.dock-order`),
# which the card writes when its published list changes -- the card's box says
# how many icons there are but not which. Pinning an app that is already running
# is the case that needs it: the height alone would only say that the pinned
# section appeared.
#
# Clicking the icon is not what proves it here. A press that lands in the moment
# the pin recommits the card's layer is swallowed -- a scan of the card puts
# kitty exactly where the helper says (y+7..y+33 of a 79px card, first icon), and
# a click there focuses it once the card has settled, but not in the same breath
# as the pin. A person cannot make that click; the click helper has its own
# scenario (`dock_click_focuses_app_test`), and this one is about the order.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window kitty
dock_settle
dock_pin '["kitty"]'

dock_wait_order "kitty foot" || fail "the pinned app is not first: the card shows '$(dock_order)'"
assert_eq "$(dock_order)" "kitty foot" "the pinned app comes before the running one"

# The column is the pinned icon, the 1px separator and the running icon, so the
# card is 79 tall -- the same arithmetic the other dock scenarios click by.
assert_eq "$(dock_box | awk '{print $4}')" 79 "the card grew by the pinned section"

dock_stop
