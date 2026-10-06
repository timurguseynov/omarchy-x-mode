# X Mode for Omarchy

A macOS-like desktop for [Omarchy](https://omarchy.org): floating windows, a Mac titlebar with same-app tabs, Rectangle-style snapping, a right-edge dock, an app switcher, and the shortcuts you already use on a Mac.

https://github.com/user-attachments/assets/0d840197-4fcf-4000-ba25-4ebfc3ff6c65

It is **additive**. The installer only creates files in its own namespace and one marked block in `~/.config/hypr/hyprland.lua`. Uninstall removes exactly what it installed.





**Floating windows · Mac titlebars · App tabs · Window snapping · Dock · App switcher · Mac shortcuts**

> Optional. Omarchy tiling stays the default until you turn X Mode on. The top-bar button turns it off again without uninstalling.

On Linux, Super is Command. The panel writes `⌘`; the tables below use `Super`.

---

## Features

* **Floating windows.** Click to focus. Everything opens floating.
* **Titlebars and tabs.** Same app on the same workspace becomes tabs of one window. The titlebar close button quits the app; a tab’s ✕ closes that tab. `+` opens another window. Drag a tab to reorder it. Colors follow the Omarchy theme.
* **Snapping.** Drag the titlebar to an edge: corners are quarters, the top edge maximizes, the sides are left and right halves. `Super+Alt+←/→` cycles `½ → ⅔ → ⅓`.
* **Dock.** Right edge, pinned and running apps, one icon per app. Click to focus or launch. Right-click for a new window, the window list, pin, or quit. Drag pins to reorder.
* **App switcher.** Hold Super and tap Tab — Command-Tab on a Mac. A row of running apps, most recently used first. Click an icon or release Super to switch.
* **Mac shortcuts.** Copy, paste, cut, screenshots, lock, fullscreen, jump by line or word, delete a word or a line, back and forward — the same keys as on a Mac.
* **Settings.** The top-bar button. Turn X Mode off to go back to Omarchy tiling. Shortcuts are configurable: a default for every app, and any one app can disagree. Settings survive uninstall.

---

## Installation

If Hyprland’s plugin headers are missing or stale, refresh them first, as your own user — not with `sudo`. `hyprpm` asks for your password itself when it needs to write `/var/cache/hyprpm`.

```bash
hyprpm update
git clone https://github.com/timurguseynov/omarchy-x-mode.git ~/omarchy-x-mode
~/omarchy-x-mode/install.sh
```

If the shell was not running, finish with `omarchy-restart-shell`.

```bash
~/omarchy-x-mode/install.sh status   # what is installed
```

---

## Uninstallation

```bash
~/omarchy-x-mode/uninstall.sh
```

Removes what the installer created. Your Hyprland and Omarchy config is left alone, and so are the panel settings in `~/.config/hypr/x-mode.json`.

To turn the desktop off without uninstalling, use the switch in the top-bar panel.

---

## Settings

The main card:

* **X Mode** on or off
* **Native scroll** — natural (reversed) scrolling
* **No gaps** — windows sit flush
* **Shortcuts** — the default for every app
* **Apps** — open one to change its titlebar and shortcuts

An app’s card:

* **Titlebar and grouping**
* **Always show tabbar** — including `+` for a single window
* **Shortcuts** — this app only

Each shortcut can stay with the desktop or go to the app, for everyone or for one app. From the main card the list is the default; from an app it is that app. A row there follows the default until you pin it Always on (green) or Always off (red) — so an editor can keep `⌘1`…`6` while titlebar tabs keep them everywhere else.

The every-app list starts with:

* **Workspaces on F1…F10.** Off, `⌘1`…`0` switch workspaces. On, `⌘F1`…`F10` do, and `⌘1`…`0` are free for titlebar tabs (or the app’s own `Ctrl+1`…`0` if Super as Ctrl is on).
* **`⌃⌘Q` locks the screen**, as on a Mac. Off leaves Omarchy’s Calculator on that key.

Then the same rows in both lists:

* **Super as Ctrl** — Super+letter becomes Ctrl+letter, so `⌘T`, `⌘R`, `⌘L` work like Command on a Mac
* **`⌘1`…`0` for titlebar tabs** — needs Workspaces on F1…F10
* **`⌃1`…`0` switches tabs** — off, those keys go to the app
* **`⌘`-click as `⌃`-click**
* **`⌃C` as `⌃⇧C`** — interrupt in a terminal; `⌘C` still copies
* Keys the desktop already uses (`⌘Q` quit, `⌘W` close, `⌘F` fullscreen, `⌘Tab` the switcher, …). Turn one on and the app gets it as Ctrl instead (`⌘W` closes a tab inside the app)

`⌘C` / `⌘V` / `⌘X` always copy, paste and cut. They are not in this list.

---

## Keyboard shortcuts

### Windows and tabs

| Shortcut | Action |
| --- | --- |
| `Super` + `Tab` | Next app |
| `Super` + `Shift` + `Tab` | Previous app |
| `Alt` + `Tab` | Next tab |
| `Alt` + `Shift` + `Tab` | Previous tab |
| `Ctrl` + `1`…`0` | Jump to tab *N* (off until enabled in Shortcuts) |
| `Super` + `1`…`0` | Jump to tab *N* (when Workspaces on F1…F10 and `⌘1`…`0` for tabs are on) |
| `Super` + `W` | Close window or tab |
| `Super` + `Q` | Quit the app |

### Snapping

| Shortcut | Action |
| --- | --- |
| `Super` + `Alt` + `←` / `→` | Snap left / right (`½ → ⅔ → ⅓`) |
| `Super` + `Alt` + `F` | Maximize |
| `Super` + `Alt` + `A` | Almost maximize |
| `Ctrl` + `Alt` + `↑` | Maximize |
| `Ctrl` + `Alt` + `↓` | Restore |
| `Ctrl` + `Alt` + `U` / `I` | Top-left / top-right |
| `Ctrl` + `Alt` + `J` / `K` | Bottom-left / bottom-right |

### Clipboard, find, fullscreen

| Shortcut | Action |
| --- | --- |
| `Super` + `C` / `V` / `X` | Copy / paste / cut |
| `Super` + `F` | Fullscreen (or Find, if Shortcuts hands `⌘F` to the app) |
| `Super` + `Ctrl` + `F` | Fullscreen |

### Screenshots, recording, lock

| Shortcut | Action |
| --- | --- |
| `Super` + `Shift` + `3` | Screenshot |
| `Super` + `Ctrl` + `Shift` + `3` | Screenshot to clipboard |
| `Super` + `Shift` + `4` | Screenshot a region |
| `Super` + `Ctrl` + `Shift` + `4` | Region to clipboard |
| `Super` + `Shift` + `5` | Screen recording |
| `Super` + `Shift` + `6` | Text from a region |
| `Super` + `Ctrl` + `Q` | Lock the screen |

### Text

| Shortcut | Action |
| --- | --- |
| `Super` + `←` / `→` | Start / end of line |
| `Super` + `↑` / `↓` | Start / end of document |
| `Super` + `Shift` + `←` / `→` | Select to start / end of line |
| `Super` + `Shift` + `↑` / `↓` | Select to start / end of document |
| `Alt` + `←` / `→` | Word left / right |
| `Alt` + `Shift` + `←` / `→` | Select word left / right |
| `Alt` + `Backspace` / `Delete` | Delete a word |
| `Super` + `Backspace` / `Delete` | Delete to start / end of line |
| `Super` + `[` / `]` | Back / forward |

### Mouse

| Action | Result |
| --- | --- |
| Drag the titlebar to an edge | Snap |
| Drag the titlebar to the top | Maximize |
| Click `+` | New window of that app |
| Drag a tab | Reorder tabs |
| Left-click a dock icon | Focus or launch |
| Right-click a dock icon | New window, window list, pin, quit |
| Drag a pinned dock icon | Reorder pins |
| `Super` + click | `Ctrl` + click (when enabled in Shortcuts) |

Move and resize from the titlebar and the window edges.

---

## License

MIT. See `LICENSE`. The vendored hyprbars is BSD 3-Clause; see [hyprbars/README.md](hyprbars/README.md).
