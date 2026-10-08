#!/usr/bin/env bash
# A floating window a client opened from another one -- a Wayland dialog, its
# toplevel has an xdg parent -- stays above the window it belongs to. Hyprland's
# CWindowState::raise lifts the whole transient stack for X11 and only the
# window itself for Wayland, and the pack keeps modal parent blocking off so a
# click on the parent stays on the parent. Focusing the parent then used to draw
# it over its own dialog, which is what put Geary's Accounts window behind the
# window that opened it.
. "$(dirname "$0")/../../lib.sh"

open_xdgchild xmode-parent xmode-dialog
assert_eq "$(topmost)" xmode-dialog "the dialog opens over its parent"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:xmode-parent' })" >/dev/null
settle
assert_eq "$(active_class)" xmode-parent "the parent took the focus"
assert_eq "$(topmost)" xmode-dialog "and the dialog is still above it"

# Once more, so the raise is not a one-off of the first focus.
nest_ctl dispatch "hl.dsp.focus({ window = 'class:xmode-dialog' })" >/dev/null
settle
assert_eq "$(topmost)" xmode-dialog "focusing the dialog keeps it on top"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:xmode-parent' })" >/dev/null
settle
assert_eq "$(active_class)" xmode-parent "the parent is focused again"
assert_eq "$(topmost)" xmode-dialog "and the parent is raised under it, not over it"
