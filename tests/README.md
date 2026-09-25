# x-mode tests

Four layers:

- **`lint/`** (via `lint.sh`) — `qmllint` over `quickshell/x-mode/*.qml`. The
  Quickshell/qs.* modules are not on the lint import path, so their "not found"
  warnings are expected; only real errors fail.
- **`unit/`** — pure Lua, no compositor: the modules in `hypr/x-mode/`
  (geometry, settings, theme, MRU).
- **`qml/`** — pure JS, no compositor: the shell plugin's shared logic in
  `quickshell/x-mode/logic.js`, run with `qmltestrunner` offscreen.
- **`nest/`** — scenarios in a nested Hyprland: a window inside the real session
  running the repo's `x-mode.lua` and the freshly built plugin, with its own
  `$X_MODE_STATE`, so nothing here touches the live session or
  `~/.local/state`.

## Run

```sh
bash tests/run.sh       # lint, unit, qml, then nest
tests/nest/run.sh       # nest only
bash tests/unit/run.sh  # pure lua only
bash tests/qml/run.sh   # pure JS only
```

Nest scenarios can be picked by name, whole or in part:

```sh
tests/nest/run.sh pointer                    # just the pointer tool's own test
tests/nest/run.sh integration/no_gaps snap   # several
tests/nest/run.sh close                      # anything whose name matches
```

A scenario's output is printed whether it passes or fails: a note it wants to
make, or a message from a tool it ran, is exactly what swallowing would hide.

The nest is one per run and `nest_clean()` runs between files, so a selected
scenario is as isolated as it is in a full run. The startup is only a few
seconds and the cost is per scenario, so selecting one is worth it: a single
scenario runs in about 4s against about 30s for the whole nest layer.

The nest runs with a runtime directory of its own, `/tmp/x-mode-nest-runtime`.
That is where its Hyprland socket, the x-mode state file and the command files
the pack writes for the switcher and the snap preview all land. It has to be
short (a unix socket path tops out around 108 bytes, and
`$XDG_RUNTIME_DIR/hypr/<signature>/.socket.sock` under `tests/.nest` runs past
that) and it has to be separate: with the real one, a keypress or a drag in the
nest would write the command files the shell of the session being used reads, and
an overlay would flash on the desktop the user is sitting in front of. Because
the directory is not the test's own, anything that connects to the nest needs
`nest_display` (the absolute socket path) rather than a bare socket name.

The nest layer builds `hyprbars` first (incrementally) and needs a running
Hyprland session (for the nest) plus the hyprpm headers. It starts one nest for
the whole run. Between files it closes the windows and restores a clean
`settings.json`, and a fresh run starts from an empty state dir: a test that
fails midway otherwise leaves settings behind that change how the next one lays
out windows.

Requirements: `hyprpm` headers (`hyprpm update`), `quickshell`/`qs` (the fake top
bar and the dock), a terminal to open test windows (`foot`, `kitty`), and Qt's
`qmllint` / `qmltestrunner` (in `/usr/lib/qt6/bin`). The two input tools need
`wayland-scanner`, the `wayland-client` headers and, for the keyboard,
`xkbcommon`. The one pixels test needs `grim` and ImageMagick's `compare`
(`magick`).

## Scenarios

| file | checks |
|---|---|
| `snap_test.sh` | halves keep the bar/gap/border inset and do not overlap |
| `group_test.sh` | a same-app window joins; the tabbar grows the chrome without pushing the visual top |
| `topbar_test.sh` | with the bar gone (shell restart) a snap still clears where it was |
| `nogaps_test.sh` | the panel's file + reload zeroes the gaps and re-lays the snapped windows |
| `focus_test.sh` | the focused window ends up topmost, including after a same-app window joins |
| `pointer_test.sh` | a titlebar drag moves the window through the drag session, and a click does not |
| `qml_test.sh` | the plugin loads in a real Quickshell (see below) |
| `integration/almost_maximize_key_test.sh` | Super+Alt+A is most of the workarea, not all of it |
| `integration/alt_tab_no_resize_test.sh` | Alt+Tab leaves the geometry alone |
| `integration/alt_tab_switches_group_tab_test.sh` | Alt+Tab and Alt+Shift+Tab move through a group's tabs |
| `integration/always_tabbar_single_tab_test.sh` | alwaysTabbar pushes a lone window down by the tabbar |
| `integration/arrange_counts_group_once_test.sh` | a group of tabs takes one half, not two |
| `integration/arrange_keeps_workspaces_test.sh` | the arrange arranges a window where it already is |
| `integration/chrome_off_drag_reaches_bar_test.sh` | without chrome the box reaches the bar |
| `integration/chrome_off_no_group_test.sh` | a chrome-off window is never grouped |
| `integration/ctrl_tab_switch_behavior_test.sh` | Ctrl+1..9 switch tabs once the option is on |
| `integration/ctrl_tab_switch_binds_test.sh` | Ctrl+1..9 binds are opt-in |
| `integration/dock_appears_test.sh` | the dock is a 40px card, centred, reserving nothing |
| `integration/dock_click_focuses_app_test.sh` | clicking an icon focuses and raises that app |
| `integration/dock_click_same_app_no_tab_switch_test.sh` | clicking the focused app's icon does not switch tabs |
| `integration/dock_click_switches_workspace_test.sh` | clicking an icon on another workspace moves there |
| `integration/dock_hides_when_x_mode_off_test.sh` | the dock follows the x-mode on/off flag |
| `integration/dock_icon_layout_test.sh` | the icon layout the click helpers assume |
| `integration/dock_menu_focuses_other_workspace_test.sh` | a window row on another workspace moves there |
| `integration/dock_menu_hides_new_for_single_instance_test.sh` | a single-instance app gets no New row |
| `integration/dock_menu_lists_windows_test.sh` | the menu lists every window and a row focuses that one |
| `integration/dock_menu_pin_writes_file_test.sh` | the menu's Pin row writes the class, and Unpin clears it |
| `integration/dock_menu_quit_closes_app_test.sh` | the menu's last row quits the app |
| `integration/dock_offset_follows_gaps_test.sh` | the dock's edge inset follows the gaps |
| `integration/dock_pinned_drag_reorders_test.sh` | dragging an icon past its neighbour rewrites the pinned order |
| `integration/dock_pinned_first_test.sh` | a pinned app's icon comes before the running ones |
| `integration/dock_pinned_shown_when_not_running_test.sh` | a pinned app that is not running still gets an icon |
| `integration/dock_right_click_menu_test.sh` | a right-click opens the context menu layer |
| `integration/dock_snap_clears_dock_test.sh` | a right-snapped window stops before the dock |
| `integration/drag_follows_pointer_live_test.sh` | mid-drag the window follows and keeps its size |
| `integration/drag_out_of_zone_test.sh` | a snapped window dragged out of its zone keeps its size |
| `integration/drag_snap_survives_new_window_test.sh` | a window opening mid-drag does not steal the snap |
| `integration/drag_snap_zones_test.sh` | side strips give halves, the top strip maximizes, corners quarter |
| `integration/drag_up_clamps_to_bar_test.sh` | dragging up leaves the chrome below the bar |
| `integration/arrow_keys_unbound_test.sh` | Cmd+arrows are unbound and do not move focus |
| `integration/follow_mouse_detached_test.sh` | follow_mouse stays 2 and a click focuses the window under the cursor |
| `integration/fullscreen_holds_others_under_test.sh` | a fullscreen window keeps the others under it |
| `integration/fullscreen_pinned_over_test.sh` | a pinned window stays above fullscreen and is raised |
| `integration/fullscreen_switcher_exits_test.sh` | Super+Tab leaves fullscreen once another app is selected |
| `integration/group_close_focus_test.sh` | closing the active tab keeps focus in the group, not on a foreign app |
| `integration/group_keys_unbound_test.sh` | Cmd+G and Cmd+Alt+G stay unbound and do not group a window |
| `integration/group_join_keeps_visual_top_test.sh` | joining a group pushes the box down instead of pinning it to the top |
| `integration/group_join_raises_test.sh` | a window joining a group raises it above another app |
| `integration/group_tab_switch_no_resize_test.sh` | switching tabs leaves the geometry alone |
| `integration/group_tabbar_click_stable_test.sh` | clicking the tabbar leaves geometry and z-order alone |
| `integration/install_arrange_halves_test.sh` | the arrange marker deals the open windows into halves once |
| `integration/join_same_app_focus_test.sh` | a new same-app window becomes the active tab, not a hidden one |
| `integration/lone_group_below_bar_test.sh` | a lone window turned into a group of one is pushed back below the bar |
| `integration/maximize_top_slop_test.sh` | the top band maximizes only inside the slop |
| `integration/maximize_via_two_bindings_test.sh` | Super+Alt+F and Ctrl+Alt+Up maximize alike |
| `integration/new_window_below_topbar_test.sh` | a new window, lone or joining a group, lands below the bar |
| `integration/no_gaps_free_window_stays_test.sh` | No gaps re-lays out a snapped window and leaves a free one alone |
| `integration/no_gaps_keeps_border_test.sh` | No gaps collapses the gaps, keeps the 1px border, and restores both |
| `integration/no_gaps_symmetric_insets_test.sh` | every inset changes with the gaps and every one comes back |
| `integration/open_window_keeps_existing_test.sh` | a window opening must not move the windows already placed |
| `integration/oversized_snap_anchors_test.sh` | a snap smaller than the client minimum keeps the snapped edge and overhangs |
| `integration/oversized_window_test.sh` | a settled window grown to twice the monitor, and where it lands |
| `integration/resnap_after_reload_test.sh` | a snapped window keeps its zone across a reload |
| `integration/same_app_across_workspaces_no_group_test.sh` | a same-app window on another space is not a tab |
| `integration/scratchpad_keys_unbound_test.sh` | Cmd+S and Cmd+Alt+S stay unbound |
| `integration/small_window_still_tabs_test.sh` | a 120x90 window is still a tab, not a popup |
| `integration/snap_cycle_chrome_off_keys_test.sh` | the cycle by key does not creep on a window without chrome |
| `integration/snap_cycle_chrome_off_test.sh` | re-snapping a window without chrome does not creep down |
| `integration/snap_cycle_thirds_test.sh` | Super+Alt+Left/Right cycle half, two thirds, a third |
| `integration/snap_geometry_stable_over_cursor_test.sh` | a snapped window does not move under a still cursor |
| `integration/snap_half_flags_test.sh` | x_mode_snap_top_half turns the strip's top into a top half |
| `integration/snap_hotkeys_maximize_restore_test.sh` | Super+Alt+F fills the workarea and Ctrl+Alt+Down restores |
| `integration/snap_hotkeys_quarters_test.sh` | Ctrl+Alt+U/I/J/K give the four quarters |
| `integration/snap_no_chrome_reaches_bar_test.sh` | without chrome a snap reaches the bar, not the titlebar inset |
| `integration/snap_preview_layer_test.sh` | the preview layer is up inside a zone while dragging and gone outside |
| `integration/snap_ungrouped_full_geometry_test.sh` | snapping one window keeps the client and makes no group |
| `integration/snap_zone_tolerance_reload_test.sh` | a vertically shifted window is put back in its zone |
| `integration/super_q_closes_app_test.sh` | Super+Q closes every tab of the app and nothing else |
| `integration/super_q_single_window_test.sh` | Super+Q on an ungrouped window closes just it |
| `integration/super_w_closes_window_test.sh` | Super+W closes the window and keeps the focus in the group |
| `integration/super_w_single_window_test.sh` | and closes an ungrouped window on its own |
| `integration/switcher_cycles_apps_test.sh` | Super+Tab cycles apps and writes the switcher's command file |
| `integration/switcher_mru_order_test.sh` | the switcher's next app is the one used before this one |
| `integration/tab_close_active_only_test.sh` | only the current tab's close button closes |
| `integration/tab_close_ignores_unfocused_group_test.sh` | a close button on an unfocused group closes nothing |
| `integration/tab_close_keeps_group_raised_test.sh` | closing the current tab keeps focus and the raise in the group |
| `integration/tab_drag_no_hang_test.sh` | a tab drag leaves the compositor answering and the group intact |
| `integration/tab_drag_reorder_test.sh` | dragging a tab rewrites the order without moving the group |
| `integration/tabbar_plus_opens_window_test.sh` | the + slot opens another window that joins the group |
| `integration/tiling_hotkeys_unbound_test.sh` | Super+O, Super+L and Super+T stay unbound |
| `integration/titlebar_click_no_raise_other_test.sh` | a titlebar click still raises the right window with No gaps on |
| `integration/titlebar_click_raises_test.sh` | clicking a titlebar focuses and raises that window |
| `integration/titlebar_click_wrong_window_test.sh` | clicking the right window raises the right window |
| `integration/titlebar_drawn_test.sh` | the titlebar band is actually painted |
| `integration/resize_after_open_clears_bar_test.sh` | a window resized after opening still clears the bar (known gap, reported) |
| `integration/titlebar_rmb_no_drag_test.sh` | a right-button drag does nothing, a left-button drag moves |

`focus_test.sh` relies on `hyprctl clients -j` being in z-order (topmost last),
which is what `lib.sh`'s helpers read.

## nest scenarios and integration scenarios

`nest/*_test.sh` checks the mechanism: a snap keeps its inset, a same-app window
joins, focus raises. `nest/integration/*_test.sh` are regressions for bugs that
actually happened, each naming the symptom in its header. Both run in the same
nest, so `run.sh` picks up both and nothing needs a second compositor.

When an assertion here hard-codes a number, say which configuration it belongs
to: `visual_top >= 36` is the gaps-on inset (bar 24 + gap 12), while with gaps
off the titlebar sits at 25 and the contract is `>= bar_top`. Comparing against
`bar_top` states the rule; a literal only states one case.

## Writing a test

Source `../lib.sh` and use its helpers:

```sh
. "$(dirname "$0")/../lib.sh"

open_window foot
snap foot left
assert_ge "$(visual_top foot)" 36 "the titlebar clears the bar"
```

Helpers: `key` (a chord in the nest), `open_window`, `open_command` (for a window
that needs arguments, like a zenity dialog), `nest_clean`, `win_geom`, `visible_geom`, `visual_top`,
`group_size`, `group_order`, `active_class`, `active_address`,
`active_tab_index`, `group_tab`, `topmost`, `bind_count`, `bind_count_desc`,
`snap`, `bar_top`, `bar_height`, `tab_height`, `tab_point`, `tab_close_point`,
`plus_point`, `viewed_workspace`, `gaps_out`, `border_size`, `plugin_option`,
`nest_ctl`, `nest_socket`, `nest_display`, `titlebar_point`, `drag_to`,
`place_frac`, `nest_screenshot`, `image_diff`, the `pointer_*` and `dock_*`
families below, and `assert_eq/ne/ge/le/between`.

Three things about the tabbar, all found the hard way:

- The tabbar is the band directly above the window box and one `tab_height`
  tall. The `+` button owns the last 34px of the width and the rest splits
  evenly, so `tab_point CLASS I N` and `tab_close_point CLASS I N` give the
  middle of a tab and of its close button (the last 24px of the tab).
- Both members of a group report `hidden: false`, so the current tab cannot be
  found that way; `active_tab_index` matches the active window's address against
  the tab order instead. A click on a background tab focuses it, so the index has
  to be re-read before the next click.
- `hyprctl keyword` refuses plugin values ('non-legacy parsers').
  `plugin_option x_mode_snap_top_half true` goes through `hyprctl eval` and
  `hl.config` instead.

`visible_geom` is `win_geom` for a group: an inactive tab stays mapped, so
`win_geom` can read a window nobody can see.

`hyprctl dispatch` here takes a dispatcher object, not the legacy string: use
`hl.dsp.window.close({ window = 'address:$addr' })`, not `killactive`.

## What there is to wait for, and what no event covers

The events a config can subscribe to on a window are: `open`, `open_early`,
`active`, `class`, `title`, `update_rules`, `move_to_workspace`, `fullscreen`,
`pin`, `urgent`, `close`, `destroy` and `kill`; alongside `config.reloaded`,
`config.props_refreshed`, the `monitor.*` and `workspace.*` families, `layer.*`
and `input.keyboard.key`. **There is no size or geometry event.**

Measuring the order for a window opened in the nest shows what that means. It
reports `class` and `title` while it is still 0x0, then `open_early`, then
`update_rules` with a provisional size, then `active`, then `open`, and then
`title` and `update_rules` again once the geometry has settled:

```
window.class        y=0   size=0
window.title        y=0   size=0
window.open_early   y=0   size=0
window.update_rules y=26  size=500
window.active       y=26  size=500
window.open         y=26  size=500
window.title        y=64  size=424     <- the settled size
window.update_rules y=64  size=424
```

That second `title` is tempting as a "the window has settled" signal, and it is
not one: it is the client writing its own title at that moment. Measured across
three clients, `foot` and `kitty` do rewrite it after settling (kitty three times
over) while `zenity` writes it once, before it has any geometry, and never again.

A resize afterwards emits **nothing at all**. With a single window: 11 events while
it opened, then 0 across a resize that moved it from y=64 to y=14 — above a bar at
24. So neither `title` nor anything else tells a scenario that the geometry moved.
`window.update_rules` is the best of a bad set — it fires repeatedly around
settling for all three clients, after as well as before the geometry stops
changing — but it does not fire on that resize either, and it fires for *every*
window whenever one opens, because Hyprland re-evaluates the rules.

So the pack cannot react, and it watches instead: `watch_until_settled` in
`x-mode.lua` runs a 50ms repeat timer for a fresh ungrouped window, re-clamps it,
and stops once two samples in a row are identical, with a 2s ceiling for a window
that never settles. That replaced two one-shot clamps at 60ms and 200ms, which a
resize could land after. It hands the window over the moment `hyprbars.drag`
reports a drag for it: a drag clamps itself in C++ and lets a window hang off an
edge, and the Lua fit would pull it back — `pointer_test.sh` caught exactly that,
which is why the handover is on the event and not on a check inside the tick.
Grouped windows are skipped, their position coming from the join; a group that
changes shape afterwards is pushed back below the bar by `push_bars_below`,
because `window.update_rules` is the only event a group change raises.

`resize_after_open_clears_bar_test.sh` holds that down: Hyprland resizes around
the window's centre, so growing a window moves its top-left up (measured at -39
with the bar at 24 before the fix), and the window has to end up clear of the bar
again.

A client can also refuse to shrink below its own minimum (kdenlive is 1027 wide
on a 938 half). Hyprland then grows the box around its centre, which walked the
left edge of a left snap off-screen (observed at x=-43). `Snap::contentBox`
grows the target to `CWindow::minSize()` and keeps the snapped edge put, so the
window overhangs the far side of its zone instead; `oversized_snap_anchors_test.sh`
holds that down.

Upstream has the fitting code but does not call it here:
`CDefaultFloatingAlgorithm::fitBoxInWorkArea()` clamps into `space->workArea(true)`
and accounts for the window's chrome through `getWindowExtentsUnified`, but it is
only reached from `newTarget()` (placement) and `movedTarget()` (moving between
monitors or workspaces) — never from a resize. The event request is
hyprwm/Hyprland#15519, unanswered. If upstream ever refits on resize, the watch
can go and a single clamp after `open` will do again.

Waiting on a fixed sleep is how a test turns flaky. `wait_for_count CLASS N
[SECONDS]` is the helper for "until it appears": a window opened through
`gtk-launch`, as the tabbar's `+` does, takes much longer on a cold start than a
plain window. And note that the pack's own launch paths inherit the nest's `HOME`,
so a window they open reads no user config at all — a `foot` launched that way has
no `foot.ini` and is unthemed.

## The pointer

`tests/pointer/` builds a small Wayland client that injects real input through
`zwlr_virtual_pointer_manager_v1`, so a scenario can click and drag a titlebar
instead of calling the pack's snap function. Hyprland turns a virtual pointer
into an ordinary `IPointer`, so a warp runs `mouseMoveUnified()` and emits
`input.mouse.move`, and a button press emits `input.mouse.button` — the two
events hyprbars' titlebar and its drag session listen to. That is why a drag
here exercises the same path a mouse does.

`lib.sh` builds it into `.nest/pointer/` (`build_pointer`, called by
`nest_start`) and exposes:

```sh
pointer_move  X Y
pointer_click X Y [BUTTON]
pointer_drag  X1 Y1 X2 Y2 [BUTTON]
pointer_press [BUTTON]
pointer_release [BUTTON]
pointer_begin / pointer_do "COMMAND" / pointer_end
```

`BUTTON` is `left` (default), `right`, `middle`, or a numeric code. Coordinates
are logical pixels in the nest's layout; the extent is taken from the monitor,
so nothing in a test has to know the monitor size. `titlebar_point CLASS`
returns the middle of a window's titlebar, which is where a drag has to start,
and `drag_to CLASS X Y` is grab-by-titlebar-and-let-go, the gesture a user makes.
`place_frac CLASS FX FY FW FH` parks a window at percentages of the monitor, so
two windows do not overlap and a click has one answer.

A process per command cannot hold a button down: the virtual pointer dies with
the process and takes the held button with it, so the gesture ends before the
next command. Scenarios that have to pause mid-gesture use one long-lived
session instead, `pointer_begin` / `pointer_do` / `pointer_end`, which drives the
tool's `hold` mode over a bash coprocess.

Two details of the real gesture, both hit while writing these tests. The first
motion after the press only crosses `binds:drag_threshold`, so the window starts
moving on the second one. And the right half stops short of the dock inset, so
its x is left of the midpoint: compare against `snap right` or check the side,
not `mw/2`.

The nest is a host window, so its logical size follows the host scale: the
900x1000 the harness asks for is 450x500 at scale 2. A hard-coded coordinate
can therefore land off the screen, and a warp past the edge is clamped, so the
click quietly hits nothing. When a scenario has to place a window itself, take
the size from `pointer_extent` and use fractions of it.

`nest/pointer_test.sh` guards the tool itself: if the protocol disappears or a
warp stops reaching `input.mouse.move`, the window does not move and every
scenario built on the pointer would fail for the wrong reason.

## Screenshots

`nest_screenshot FILE` captures the nest with `grim`, and `image_diff A B` returns
how many pixels differ. That is the only way to check something that is only
pixels — the titlebar is drawn into the window's own render pass, so there is no
layer or property to ask about.

Two things to know. grim captures the output in physical pixels while the geometry
helpers are logical, so a region has to be scaled by the monitor's scale. And grim
against a nested compositor sometimes fails to get a buffer, and a shot taken
mid-frame is not what a comparison wants, so `nest_screenshot` settles and retries,
and a test should take a shot it does not look at before the one it compares.
Comparisons want a band that changes and a control band that does not, or a torn
frame reads as a change.

## The keyboard

`tests/keyboard/` presses key combinations in the nest:

```sh
key super+alt+left        # the snap cycle
key alt+tab               # next tab of the group
key o                     # a plain key
key -d 5 a b c            # several keys, 5ms apart
```

Why a tool of our own, when `wtype` is installed: `wtype` types into a client but
no keybind fires. Hyprland's `CKeybindManager::onKeyEvent` resolves the pressed
key through `m_xkbTranslationState`, the compositor's own keymap, while a client
gets its keysym from the device's keymap, and `wtype` sends a synthetic keymap of
its own with its own keycode numbering. So the two disagree and nothing matches —
`logo`/`win`/`mod4`, raw keycodes and delays between the modifier and the key all
made no difference.

So this sends the keymap `xkbcommon` builds from the system rules (pc105/us), the
same layout Hyprland resolves against, and presses keys with libinput-style
codes: Hyprland does `keycode + 8` before the xkb lookup, which lands on the
standard XKB keycode only when the client sends the evdev code. The modifier mask
comes from an xkb state built on that same keymap, so Mod4 really is 64, and the
tool founds the keycode by looking for the key that produces the wanted symbol,
so a test only names symbols.

`lib.sh` builds it into `.nest/keyboard/` (`build_keyboard`) and exposes `key`.
Requires the `xkbcommon` headers as well as `wayland-scanner`.

The bind *table* is still worth checking where the behaviour is what matters
(`bind_count`, `bind_count_desc`): those catch a bind coming back or never being
installed, which a keypress test cannot see. Note that a bind made with a raw
keycode (`CTRL + code:10`) reports an empty `key`, which is why the description is
needed there.

## The dock

The dock is a Quickshell layer surface, so a scenario that needs it starts a
Quickshell of its own against the nest (the same trick as `nest/qml_test.sh`),
and the pointer tool reaches its icons because both talk to the nest:

```sh
dock_start
open_window foot
open_window kitty
dock_settle
read -r px py <<<"$(dock_icon_point 1)"
pointer_click "$px" "$py"
dock_stop
```

`dock_icon_point INDEX` computes the middle of the INDEXth icon: the card is
`iconSize + 2*pad` wide (26 + 14), the column is centred in it, and icons stack
with `iconSpacing` (6) between them, so the first centre is `pad + iconSize/2`
below the card's top. `dock_icon_layout_test.sh` pins that arithmetic, because
every other dock click depends on it. Icons are ordered pinned first, then by
class, so with only foot and kitty the icons are 0 and 1.

`dock_layer_box NAMESPACE` finds a layer's box; the menu is a layer called
`x-mode-dock-menu`, which is how a right-click can be observed at all.

A third app for the switcher's order test comes from `foot --app-id=...`, which
Hyprland reads as the class: a dialog would work too, but a `zenity --info` puts
an "Information" window on screen for the whole run.

`dock_pin '["kitty"]'` writes the pinned list the dock reads from its HOME (the
nest's, thanks to the redirected HOME above), and `dock_menu_row_point`
computes the middle of a menu row. Pass it the row-height list the test expects
(26 for a row, 7 for a separator) so the click says which menu it is aiming at.
For a running app with one window that is `"26 7 26 7 26 26"`: New, separator,
the window row, separator, Pin/Unpin, Quit. `Quit` is the last row of every menu
the dock builds, so it can be aimed at without knowing the rows above it.

What the menu rows do is covered, but the ones that *launch* are not: they shell
out through `uwsm-app` and `gtk-launch`, which hang in the nest (no uwsm session),
so a test that clicked them would block instead of failing. Pin/Unpin and Quit act
locally and are tested.

`nest_clean()` also clears the pinned file and any desktop entries written into
the dock's HOME, and switches back to the first workspace: all three outlive one
scenario. Without the first two a dock test starts with the previous one's icons,
and a leftover single-instance entry changes the menu for the class it names,
shifting the rows the menu tests click on. Without the third, a scenario that
switches workspace decides where the next one opens its windows — two same-app
windows that land on one space group instead of staying apart, which is how the
workspace test above failed in a full run while passing alone.

The dock runs with the nest's own runtime directory and `HOME` (see the Run
section): the same-isolation reasons apply, and it needs both, because the state
file the plugin reads and the command files it writes all live there, and because
the pinned list belongs in the nest's HOME rather than the user's.

`nest/run.sh` stops the dock on exit, so a scenario that fails midway cannot
leave a Quickshell running against the nest.

## unit layer

Pure logic that does not need a compositor. It lives in sibling modules next to
`x-mode.lua`, so the tests load them directly with plain `lua`:

| file | module | covers |
|---|---|---|
| `geometry_test.lua` | `hypr/x-mode/geom.lua` | frame (including scale), zone insets with and without gaps, halves not overlapping, maximize, almost-maximize, cycle sizes, `fit_box` clamping, `cycle_index` |
| `settings_test.lua` | `hypr/x-mode/settings.lua` | options/apps parsing, the apps section vs the whole file, the legacy array, the merge of the two old files, the rule diff |
| `theme_test.lua` | `hypr/x-mode/theme.lua` | the TOML subset (inline comments, quotes), hex/rgb conversion, the bar color defaults |
| `mru_test.lua` | `hypr/x-mode/mru.lua` | touch ordering, step wrapping, sort by MRU then focus |

Adding to a module is the way to make something unit-testable: `x-mode.lua`
still holds the event/state layer (binds, `hl.dispatch`, grouping, switcher),
which the nest layer exercises instead.

## qml layer

Same idea for the shell plugin: the pure JS it shares lives in
`quickshell/x-mode/logic.js` (`.pragma library`), so it can be tested with
`qmltestrunner` offscreen, without a Quickshell runtime.

| file | covers |
|---|---|
| `tst_logic.qml` | `parseEnabled` (on/off/1/0/true/false/empty/junk), `shellQuote`, `parseApps` (object, legacy array, invalid), `cleanName`, `lastSegment`, `webappHostFromExec`, `parseSwitcherCmd`, `parseSnapCmd`, `rectsIntersect` |

What is *not* unit-testable this way: the components themselves. `import
Quickshell` fails under `qmltestrunner` (`plugin "quickshell-coreplugin" not
found`) — the Quickshell types are linked into the Quickshell binary, there is no
plugin to dlopen.

So a component is exercised by `nest/qml_test.sh`, which starts a real
Quickshell with a minimal config that instantiates the plugin's Dock against the
nest and checks it comes up. That catches what `qmllint` cannot: a broken
import, a binding that throws, a missing property.

The config folder has to provide the `qs.*` modules the plugin imports
(`Quickshell` resolves them relative to the config), so the test symlinks
Omarchy's `Commons`/`Ui` into it, and imports the plugin by `file:` URL (an
absolute path import is rejected).

Add to `logic.js` to make more of the plugin testable without a compositor.
