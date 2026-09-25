#!/usr/bin/env bash
# A pinned app is shown even when it is not running, which is what pinning is
# for. The column is then the pinned icon, the 1px separator and the running
# icon: 26 + 6 + 1 + 6 + 26 of icons plus the 14 of padding.
#
# Pinned before the dock starts, so the file is read at load.
. "$(dirname "$0")/../../lib.sh"

dock_pin '["kitty"]'
dock_start
open_window foot
dock_settle

assert_eq "$(dock_box | awk '{print $4}')" 79 \
  "a pinned app that is not running still gets an icon"

dock_stop
