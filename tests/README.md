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

The nest is one per run and `nest_clean()` runs between files, so a selected
scenario is as isolated as it is in a full run. The startup is only a few
seconds and the cost is per scenario, so selecting one is worth it: a single
scenario runs in about 4s against about 30s for the whole nest layer.

The nest layer builds `hyprbars` first (incrementally) and needs a running
Hyprland session (for the nest) plus the hyprpm headers. It starts one nest for
the whole run. Between files it closes the windows and restores a clean
`settings.json`, and a fresh run starts from an empty state dir: a test that
fails midway otherwise leaves settings behind that change how the next one lays
out windows.

Requirements: `hyprpm` headers (`hyprpm update`), `quickshell`/`qs` (the fake top
bar), a terminal to open test windows (`foot`, `kitty`), and Qt's `qmllint` /
`qmltestrunner` (in `/usr/lib/qt6/bin`). The pointer tool also needs
`wayland-scanner` and the `wayland-client` headers.

## Scenarios

| file | checks |
|---|---|
| `snap_test.sh` | halves keep the bar/gap/border inset and do not overlap |
| `group_test.sh` | a same-app window joins; the tabbar grows the chrome without pushing the visual top |
| `topbar_test.sh` | with the bar gone (shell restart) a snap still clears where it was |
| `nogaps_test.sh` | the panel's file + reload zeroes the gaps and re-lays the snapped windows |
| `focus_test.sh` | the focused window ends up topmost, including after a same-app window joins |
| `pointer_test.sh` | a titlebar drag moves the window through the drag session, and a click does not |
| `integration/open_window_keeps_existing_test.sh` | a window opening must not move the windows already placed |
| `integration/no_gaps_keeps_border_test.sh` | No gaps collapses the gaps, keeps the 1px border, and restores both |
| `integration/group_close_focus_test.sh` | closing the active tab keeps focus in the group, not on a foreign app |
| `integration/join_same_app_focus_test.sh` | a new same-app window becomes the active tab, not a hidden one |
| `integration/group_join_keeps_visual_top_test.sh` | joining a group pushes the box down instead of pinning it to the top |
| `integration/group_tab_switch_no_resize_test.sh` | switching tabs leaves the geometry alone |
| `integration/snap_cycle_chrome_off_test.sh` | re-snapping a window without chrome does not creep down |
| `integration/no_gaps_free_window_stays_test.sh` | No gaps re-lays out a snapped window and leaves a free one alone |
| `integration/follow_mouse_detached_test.sh` | follow_mouse stays 2 and a click focuses the window under the cursor |
| `integration/snap_ungrouped_full_geometry_test.sh` | snapping one window keeps the client and makes no group |
| `integration/install_arrange_halves_test.sh` | the arrange marker deals the open windows into halves once |
| `integration/no_gaps_symmetric_insets_test.sh` | every inset changes with the gaps and every one comes back |
| `integration/titlebar_rmb_no_drag_test.sh` | a right-button drag does nothing, a left-button drag moves |
| `integration/drag_snap_zones_test.sh` | side strips give halves, the top strip maximizes, corners quarter |
| `integration/drag_up_clamps_to_bar_test.sh` | dragging up leaves the chrome below the bar |
| `integration/drag_follows_pointer_live_test.sh` | mid-drag the window follows and keeps its size |
| `integration/snap_geometry_stable_over_cursor_test.sh` | a snapped window does not move under a still cursor |
| `integration/titlebar_click_raises_test.sh` | clicking a titlebar focuses and raises that window |
| `integration/titlebar_click_wrong_window_test.sh` | clicking the right window raises the right window |
| `integration/group_tabbar_click_stable_test.sh` | clicking the tabbar leaves geometry and z-order alone |
| `integration/snap_no_chrome_reaches_bar_test.sh` | without chrome a snap reaches the bar, not the titlebar inset |
| `integration/chrome_off_no_group_test.sh` | a chrome-off window is never grouped |
| `integration/tabbar_plus_opens_window_test.sh` | the + slot opens another window that joins the group |
| `integration/tab_close_keeps_group_raised_test.sh` | closing the current tab keeps focus and the raise in the group |
| `integration/tab_close_ignores_unfocused_group_test.sh` | a close button on an unfocused group closes nothing |
| `integration/tab_close_active_only_test.sh` | only the current tab's close button closes |
| `integration/tab_drag_reorder_test.sh` | dragging a tab rewrites the order without moving the group |
| `integration/tab_drag_no_hang_test.sh` | a tab drag leaves the compositor answering and the group intact |
| `integration/drag_snap_survives_new_window_test.sh` | a window opening mid-drag does not steal the snap |
| `integration/maximize_top_slop_test.sh` | the top band maximizes only inside the slop |
| `integration/snap_half_flags_test.sh` | x_mode_snap_top_half turns the strip's top into a top half |
| `integration/chrome_off_drag_reaches_bar_test.sh` | without chrome the box reaches the bar |
| `integration/always_tabbar_single_tab_test.sh` | alwaysTabbar pushes a lone window down by the tabbar |
| `integration/titlebar_click_no_raise_other_test.sh` | a titlebar click still raises the right window with No gaps on |
| `integration/snap_zone_tolerance_reload_test.sh` | a vertically shifted window is put back in its zone |
| `integration/tiling_hotkeys_unbound_test.sh` | Super+O, Super+L and Super+T stay unbound |
| `integration/ctrl_tab_switch_binds_test.sh` | Ctrl+1..9 binds are opt-in |
| `integration/group_join_raises_test.sh` | a window joining a group raises it above another app |
| `integration/drag_out_of_zone_test.sh` | a snapped window dragged out of its zone keeps its size |
| `integration/new_window_below_topbar_test.sh` | a new window, lone or joining a group, lands below the bar |
| `integration/resnap_after_reload_test.sh` | a snapped window keeps its zone across a reload |
| `qml_test.sh` | the plugin loads in a real Quickshell (see below) |

`focus_test.sh` relies on `hyprctl clients -j` being in z-order (topmost last),
which is what `lib.sh`'s helpers read.

## Writing a test

Source `../lib.sh` and use its helpers:

```sh
. "$(dirname "$0")/../lib.sh"

open_window foot
snap foot left
assert_ge "$(visual_top foot)" 36 "the titlebar clears the bar"
```

Helpers: `open_window`, `nest_clean`, `win_geom`, `visible_geom`, `visual_top`,
`group_size`, `group_order`, `active_class`, `active_address`,
`active_tab_index`, `group_tab`, `topmost`, `bind_count`, `bind_count_desc`,
`snap`, `bar_top`, `bar_height`, `tab_height`, `tab_point`, `tab_close_point`,
`plus_point`, `gaps_out`, `border_size`, `plugin_option`, `nest_ctl`,
`nest_socket`, `titlebar_point`, `drag_to`, `place_frac`, the `pointer_*` family
below, and `assert_eq/ne/ge/le/between`.

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

## nest scenarios and integration scenarios

`nest/*_test.sh` checks the mechanism: a snap keeps its inset, a same-app window
joins, focus raises. `nest/integration/*_test.sh` are regressions for bugs that
actually happened, each naming the symptom in its header. Both run in the same
nest, so `run.sh` picks up both and nothing needs a second compositor.

When an assertion here hard-codes a number, say which configuration it belongs
to: `visual_top >= 36` is the gaps-on inset (bar 24 + gap 12), while with gaps
off the titlebar sits at 25 and the contract is `>= bar_top`. Comparing against
`bar_top` states the rule; a literal only states one case.

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

## Keybinds cannot be driven from here

There is no way to press a modified keybinding in the nest. `wtype` is installed
and typing works: characters reach the focused client, verified by typing a
command into a shell inside the nest. But no keybind fires, not even an
unmodified one.

The reason is in Hyprland. `CKeybindManager::onKeyEvent` resolves the pressed key
through `m_xkbTranslationState`, the compositor's own keymap, while a client gets
its keysym from the device's keymap. `wtype` sends a synthetic keymap of its own
with its own keycode numbering, so the two disagree and nothing matches. `-P`
sends a raw keycode but goes through the same translation, and no variant helped:
`logo`, `win`, `mod4`, raw keycodes, delays between the modifier and the key.

So the tiling-hotkey and Ctrl+N contracts are pinned at the bind table instead
(`bind_count`, `bind_count_desc`). That catches a bind coming back or never being
installed, but not the keypress itself. Note that a bind made with a raw keycode
(`CTRL + code:10`) reports an empty `key`, which is why the description is needed
there.

A small tool that sends a keymap using the standard keycode numbering would fix
this the way the pointer tool fixed gestures. The drafts waiting on it are the
snap cycle (½ → ⅔ → ⅓) and the tab switch that has to raise its group.

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
