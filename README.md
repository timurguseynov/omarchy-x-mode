# X Mode for Omarchy

A macOS-like desktop layer for [Omarchy](https://omarchy.org): floating windows, a Mac titlebar with same-app tabs, Rectangle-style snapping, a right-edge dock, and an app switcher.

https://github.com/user-attachments/assets/0d840197-4fcf-4000-ba25-4ebfc3ff6c65

It is **additive**. The installer only creates files in its own namespace and one marked block in `~/.config/hypr/hyprland.lua`. Uninstall removes exactly what it installed.





**Floating windows · Mac titlebars · App tabs · Window snapping · Dock · App switcher**

> Optional profile. Omarchy tiling stays the default until you turn X Mode on. The top-bar button turns it off again without uninstalling.

---

## Key Features

* **Floating desktop.** Windows open floating, with click-to-focus and no pointer warping. Tiling shortcuts (`Super+T`, layout picker, keyboard resize) are unbound while X Mode is on.
* **Mac titlebars and tabs.** A patched [hyprbars](hyprbars/README.md) draws the titlebar and a tab strip, colored from the current Omarchy theme. Windows of the same app on the same workspace group automatically; a new window joins the existing group instead of flashing in the middle. The titlebar close button quits the whole group; a tab’s ✕ closes that tab, and only the focused one. `+` opens another window. Drag a tab to reorder it.
* **Rectangle-style snapping.** Drag a window by its titlebar to a screen edge for a live preview: corners are quarters, the top edge maximizes, and the side edges are left/right halves. The right edge stops short of the dock. `Super+Alt+←/→` cycles `½ → ⅔ → ⅓`. On a fresh install, and again when you turn X Mode back on, already-open windows are dealt out again: one group per app, spread across the left and right halves, and a workspace with a single group has that group centred instead.
* **Right-edge dock.** Pinned and running apps, one icon per app. It floats over windows and does not reserve space. Left-click focuses the app’s window on this workspace, or its most recently focused window on another workspace, and launches a pinned app that is not running. Right-click opens a menu: new window (unless the app is single-instance), its open windows sorted by workspace, pin/unpin, and quit. Drag pinned icons to reorder them. Pins are kept in `~/.config/omarchy/x-mode-dock.json`.
* **App switcher (`Super+Tab`).** A centered row of running apps, most recently used first. The row stays up while Super is held; click an icon or release Super to land on the highlighted app.
* **Settings panel.** The top-bar button opens:
  * X Mode on or off. Off ungroups every window and puts it back to the floating or tiled state it had before X Mode was installed
  * Natural (reversed) scrolling, for both mouse and touchpad
  * No gaps: no space between windows, with a hairline border kept. This is the desktop's only gaps switch: Omarchy's own `⇧⌘⌫` toggle has its key taken away and its saved state retired on every load, with the reload that puts the gaps back, since two switches for one setting fight over the values
  * Per-app titlebar and grouping
  * Always show the tab bar, including the `+` for a single window
  * Shortcuts, one screen for the whole desktop and one per app. The "for every app" screen opens with the desktop's rows:
    * Workspaces on `Super`+`F1`…`F10`: off, `Super`+`1`…`0` switch workspaces as Omarchy ships them; on, the F keys do, and the ten freed digits follow that app's Shortcuts
    * `⌃⌘Q` locks the screen, the Mac key for it. Omarchy keeps its Calculator there and locks on `⌃⌘L`, so this one takes that key; off hands it back to the Calculator
    * then the shortcuts themselves: `⌃`+`1`…`0` switching the pack's tabs (off by default, so the keys reach the app), `Super as Ctrl`, `⌘1`…`0` reserved for the pack's tabs, `⌘`-click as `⌃`-click, `⌃C` as `⌃⇧C`, and every occupied key (`⌘Q`, `⌘W`, `⌘Tab`, …) with the desktop action it replaces
  * Every shortcut is a switch *and* a per-app three-state: a row in an app's card follows the desktop by default, and clicking it cycles through Always on (a green edge) and Always off (a red one) before going back to following. That is what lets one app disagree with the desktop — `⌘`+`1`…`6` handed to an editor as its own `Ctrl`+`1`…`6` while the pack's tabs keep them everywhere else, and its physical `Ctrl`+`1`…`6` left to it too
  * macOS capture keys: `⇧⌘3` screenshots the screen, `⇧⌘4` a region you drag, `⌃⇧⌘3`/`⌃⇧⌘4` the same to the clipboard, `⇧⌘5` screen recording, `⇧⌘6` reads text out of a region
  * macOS text chords: `⌘←`/`⌘→` start and end of line, `⌘↑`/`⌘↓` the document, `⌥←`/`⌥→` a word, `⌥⌫`/`⌥⌦` delete a word, `⌘⌫`/`⌘⌦` delete to the start and end of the line, `⌘[`/`⌘]` back and forward — each sent as the chord the focused app understands (a terminal gets readline's, everything else its toolkit's)
  * Per-app: `Ctrl`+`C` as `Ctrl`+`Shift`+`C`, for an app with a terminal inside: the key goes in shifted so the app's own binding can make it the interrupt, while `Super`+`C` still copies

---

## Keyboard Shortcuts

> `Super` is your primary modifier (Windows / Command).

### Windows and tabs

| Shortcut | Action |
| --- | --- |
| `Super` + `Tab` | Next app (switcher stays while Super is held) |
| `Super` + `Shift` + `Tab` | Previous app |
| `Alt` + `Tab` | Next tab in the focused group |
| `Alt` + `Shift` + `Tab` | Previous tab in the focused group |
| `Ctrl` + `1`…`9` | Jump to tab *N*. Off until enabled in the panel, so the keys reach the app |
| `Super` + `W` | Close the active window or tab. Per-app, send `Ctrl`+`W` so the tab closes and the window stays |
| `Super` + `Q` | Quit the app (every tab in the group) |

### Snapping

| Shortcut | Action |
| --- | --- |
| `Super` + `Alt` + `←` / `→` | Snap left / right (cycles `½ → ⅔ → ⅓`) |
| `Super` + `Alt` + `F` | Maximize |
| `Super` + `Alt` + `A` | Almost-maximize (90% of the work area, centered) |
| `Ctrl` + `Alt` + `↑` | Maximize |
| `Ctrl` + `Alt` + `↓` | Restore the size from before the last snap |
| `Ctrl` + `Alt` + `U` / `I` | Top-left / top-right quarter |
| `Ctrl` + `Alt` + `J` / `K` | Bottom-left / bottom-right quarter |

### Mouse

| Action | Result |
| --- | --- |
| Drag the titlebar to an edge | Snap, with a live preview |
| Drag the titlebar to the top edge | Maximize |
| Click `+` on the tab strip | Open another window of that app |
| Drag a tab | Reorder tabs in the group |
| Left-click a dock icon | Focus the running app, or launch it |
| Right-click a dock icon | New window, window list, pin/unpin, quit |
| Drag a pinned dock icon | Reorder pins |

`Super` + drag is disabled. Move and resize a window from its titlebar and edges.

---

## Installation

X Mode reloads hyprpm plugins on startup. If the Hyprland header cache is missing or stale, that reload reports `Failed to load plugins: Outdated headers. Please run hyprpm update manually.` Refresh the cache first, as your own user. `hyprpm` refuses to run under `sudo` (`Don't run hyprpm as a superuser`) and asks for your password itself when it needs to write `/var/cache/hyprpm`.

```bash
hyprpm update
git clone https://github.com/timurguseynov/omarchy-x-mode.git ~/omarchy-x-mode
~/omarchy-x-mode/install.sh
```

The installer builds the patched hyprbars, copies the shell plugin and the `x-mode` config directory into `~/.config/hypr/`, reloads Hyprland, floats windows that are already open, and restarts the shell. If the shell was not running, finish with `omarchy-restart-shell`.

```bash
~/omarchy-x-mode/install.sh status   # what is installed
```

The patched hyprbars is part of the install. It is the titlebar, the tab strip
and the snapping, the keys included, so there is nothing to install without it.

---

## Uninstallation

```bash
~/omarchy-x-mode/uninstall.sh
```

This removes the plugin, the sentinel block, and the files the installer created. It also ungroups windows and puts them back to the floating-or-tiled state they had before install. Your own Hyprland and Omarchy config is left alone, and so are the panel's settings in `~/.config/hypr/x-mode.json`: reinstall and they are back.

To turn the desktop off without uninstalling, use the switch in the top-bar panel.

---

## License

MIT. See `LICENSE`. The vendored hyprbars is BSD 3-Clause; see [hyprbars/README.md](hyprbars/README.md).
