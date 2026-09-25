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
`group_size`, `active_class`, `active_address`, `group_tab`, `topmost`, `snap`,
`bar_top`, `gaps_out`, `border_size`, `nest_ctl`, `nest_socket`,
`titlebar_point`, the `pointer_*` family below, and
`assert_eq/ne/ge/le/between`.

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

## What needs more than the pointer

Some scenarios drive a keybinding, and there is no way to press a key here yet:
the tab switch that has to raise its group, and the tiling hotkeys that must
stay unbound. Both were reported live and are not covered.

`hl.dsp.group.active`, the dispatcher the pack's Ctrl+N handler calls, switches
the tab but does not focus the group: the focus and the raise come from the
focus handler, which only runs when the group already has focus. So driving the
dispatcher from a test does not reproduce the Alt+Tab case. A virtual keyboard
(`zwp_virtual_keyboard_manager_v1`) is the same trick as the pointer and is what
this needs.

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
