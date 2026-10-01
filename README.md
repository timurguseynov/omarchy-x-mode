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
* **Rectangle-style snapping.** Drag a window by its titlebar to a screen edge for a live preview: corners are quarters, the top edge maximizes, and the side edges are left/right halves. The right edge stops short of the dock. `Super+Alt+←/→` cycles `½ → ⅔ → ⅓`. On a fresh install, and again when you turn X Mode back on, already-open windows are spread across the left and right halves, one side per app.
* **Right-edge dock.** Pinned and running apps, one icon per app. It floats over windows and does not reserve space. Left-click focuses the app’s window on this workspace, or its most recently focused window on another workspace, and launches a pinned app that is not running. Right-click opens a menu: new window (unless the app is single-instance), its open windows sorted by workspace, pin/unpin, and quit. Drag pinned icons to reorder them. Pins are kept in `~/.config/omarchy/x-mode-dock.json`.
* **App switcher (`Super+Tab`).** A centered row of running apps, most recently used first. The row stays up while Super is held; click an icon or release Super to land on the highlighted app.
* **Settings panel.** The top-bar button opens:
  * X Mode on or off. Off ungroups every window and puts it back to the floating or tiled state it had before X Mode was installed
  * Natural (reversed) scrolling, for both mouse and touchpad
  * `Ctrl`+`1`…`9` switches tabs. Off by default, so the keys reach the app
  * Workspaces on `Super`+`F1`…`F10`: off, `Super`+`1`…`0` switch workspaces as Omarchy ships them; on, the F keys do and the digits are left for the app
  * No gaps: no space between windows, with a hairline border kept
  * Per-app titlebar and grouping
  * Always show the tab bar, including the `+` for a single window
  * Per-app: send `Ctrl`+`W` on `Super`+`W`, so the tab closes and the window stays
  * Per-app: `Super` works as `Ctrl`, so unbound `Super`+key reaches the app as `Ctrl`+key. The keys the desktop already uses stay put, `Super`+`Tab` included
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
