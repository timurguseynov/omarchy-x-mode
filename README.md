# A Mac-like desktop for Omarchy

**X Mode** — floating windows, a Mac titlebar with same-app tabs, Rectangle-style snapping, a right-edge dock, Command-Tab, and the shortcuts you already use on macOS — on [Omarchy](https://omarchy.org). Coming from a Mac, or already tiling: Linux and Omarchy stay, and so do the controls. How the windows are kept does not.

> Optional. Omarchy tiling stays the default. The top-bar button turns X Mode off; nothing to reinstall.

## How it's meant to be used

> Never minimize or hide windows. Spaces are only for something extra. Snaps and tabs arrange the windows, so they can sit on top of each other, and you never think about spaces, hiding or where you put a window. The dock is always on for fast access.

https://github.com/user-attachments/assets/d1749801-e1cb-4fc9-a65a-03313b7797a8



**Floating windows · Mac titlebars · App tabs · Window snapping · Dock · App switcher · Mac shortcuts**

[How it's meant to be used](#how-its-meant-to-be-used) · [Features](#features) · [Installation](#installation) · [Uninstallation](#uninstallation) · [Settings](#settings) · [Keyboard shortcuts](#keyboard-shortcuts) · [License](#license)

---

## Features

The Mac habits that keep you fast — on Omarchy.

* **Floating windows, as a layout.** Omarchy 4.5 gives every workspace a mode — tiling, scrolling, floating — and X Mode adds its own, `xmode`, to the same list. On an `xmode` workspace everything opens floating, with the titlebar, the tabs and the snaps below; on every other mode the pack stays out of the way and Omarchy's layout owns the window. `Super+L` walks the ring (`tiling → scrolling → floating → xmode`), `Super+Alt+L` walks it back, and *Appearance → Workspace Layout* in the Omarchy menu sets the default.
* **Titlebars like a Mac.** A window moves by the titlebar, closes with the button.
* **Tabs in every app.** Like native tabs on a Mac, but for every app you choose: two windows of the same app on a workspace become tabs of one window.
* **Compact tabs.** One Chrome-like titlebar row instead of titlebar plus tabbar. Tabs stay a limited width; leftover space after `+` drags the window. On for every app, or for one.
* **Snaps.** Rectangle-like snapping from the titlebar: drag to a side for a half, a corner for a quarter, the top edge to maximize. `Super+Alt+←/→` cycles `½ → ⅔ → ⅓`.
* **The Dock.** The familiar column of pinned and running apps, on the right edge. Click to focus or launch, right-click for a new window, the window list, pin or quit, drag pins to reorder. A new app joins the bottom of the running icons, the way it does on a Mac.
* **Command-Tab.** Hold Super and tap Tab — the app switcher you use all day, most recently used first. Click an icon or release Super to switch.
* **The rest of the Mac keys.** Copy, paste and cut Omarchy already does. X Mode adds `Super+←`/`→` by line, `Super+↑`/`↓` by document, `Alt+←`/`→` by word, deleting a word, or to the start and end of the line, `Super+[`/`]` back and forward (or moving code, from Shortcuts), `Super+Shift+3…5` screenshots and `Super+Ctrl+Q` lock. Shortcuts are configurable app by app, so the Mac experience stays seamless even where one app disagrees.
* **The settings panel.** Open it from the top-bar button: X Mode on or off, per-app titlebars and grouping, and the shortcuts. Settings survive uninstall.

---

## Installation

Needs Omarchy v4 or newer.

The installer is additive: it only creates files in its own namespace and one marked block in `~/.config/hypr/hyprland.lua`. A stock Hyprland hyprbars, if you have one, is turned off while X Mode's patched build runs.

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

## Workspace modes

Omarchy keeps a mode per workspace in `~/.local/state/omarchy/workspace-layouts` and
replays those files at every login, so a workspace stays where you put it.

* `xmode` is the pack's own mode: floating windows, titlebars, tabs, snaps, and the
  Mac keys.
* Tiling, scrolling and Omarchy's floating are hers: the pack draws no titlebar
  there, does not group there, does not snap there, and hands the tiling keys back
  to her — `Super+←/→` focuses, `Super+T` floats, the resize steps resize, and so on.
* `Super+L` cycles a workspace through all four, `Super+Alt+L` cycles back. The same
  cycle is in the bar's layout menu, and *Appearance → Workspace Layout* sets the
  mode new workspaces get.
* `~/.config/hypr/x-mode/xmode` is the script behind both: `xmode next`, `xmode back`,
  `xmode current [workspace]`, `xmode set <workspace> <mode>`, `xmode default [mode]`.

## Uninstallation

```bash
~/omarchy-x-mode/uninstall.sh
```

Removes what the installer created, and turns a stock hyprbars back on if it was disabled. Your Hyprland and Omarchy config is left alone, and so are the panel settings in `~/.config/hypr/x-mode.json`.

---

## Settings

The main card:

* **X Mode** on or off
* **Native scroll** — natural (reversed) touchpad scrolling
* **No gaps** — windows sit flush, on an xmode workspace only
* **Compact tabs** — tabs in the titlebar, for every app
* **Shortcuts** — the default for every app
* **Apps** — open one to change its titlebar and shortcuts

An app’s card:

* **Titlebar and grouping**
* **Always show tabbar** — including `+` for a single window
* **Compact tabs** — tabs in the titlebar
* **Shortcuts** — this app only

Each shortcut can stay with the desktop or go to the app, for everyone or for one app. From the main card the list is the default; from an app it is that app. A row there follows the default until you pin it Always on (green) or Always off (red) — so an editor can keep `⌘1`…`6` while titlebar tabs keep them everywhere else.

The every-app list starts with:

* **Workspaces on F1…F10.** Off, `⌘1`…`0` switch workspaces. On, `⌘F1`…`F10` do, and `⌘1`…`0` are free for titlebar tabs (or the app’s own `Ctrl+1`…`0` if Super as Ctrl is on).
* **`⌃⌘Q` locks the screen**, as on a Mac. Off leaves Omarchy’s Calculator on that key.

Then the same rows in both lists:

* **Super as Ctrl** — Super+letter and Super+punctuation become Ctrl+letter and Ctrl+punctuation, so `⌘T`, `⌘R`, `⌘L` and `⌘⇧\` work like Command on a Mac
* **`⌘1`…`0` switch tabs** — needs Workspaces on F1…F10
* **`⌃1`…`0` switch tabs** — works without it; off, they switch the app’s own tabs (browser, editor)
* **`⌘`-click as `⌃`-click**
* **`⌃C` as `⌃⇧C`** — interrupt in a terminal; `⌘C` still copies
* **`⌘[` `⌘]` move code** — outdent and indent, the way an editor binds `Ctrl+[` / `Ctrl+]`. Off, the same keys go back and forward
* **`⌘⇧T` reopen tab** — the app's `Ctrl+Shift+T` (the last closed tab). Off, Omarchy's Activity keeps the key
* Keys the desktop already uses (`⌘Q` quit, `⌘W` close, `⌘F` fullscreen, `⌘Tab` the switcher, …). Turn one on and the app gets it as Ctrl instead (`⌘W` closes a tab inside the app)

`⌘A` / `⌘C` / `⌘V` / `⌘X` always select all, copy, paste and cut. They are not in this list.

---

## Keyboard shortcuts

Super is Command (`⌘` in the panel).

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
| `Super` + `Shift` + `T` | Reopen the closed tab (off until enabled in Shortcuts) |

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
| Click `+` on the tabbar | New window of that app |
| Drag leftover after `+` (compact tabs) | Move the window |
| Drag a tab | Reorder tabs |
| Left-click a dock icon | Focus or launch |
| Right-click a dock icon | New window, window list, pin, quit |
| Drag a pinned dock icon | Reorder pins |
| `Super` + click | `Ctrl` + click (when enabled in Shortcuts) |

Move and resize from the titlebar and the window edges.

---

## License

MIT. See `LICENSE`. The vendored hyprbars is BSD 3-Clause; see [hyprbars/README.md](hyprbars/README.md).

---

## Donations

- **EVM Chains (ETH, USDT, USDC, Base, Polygon, Arbitrum, BSC, Linea):** `0x581751947baDFf4c46C7A28a96Cf3F5708a7f930`
- **USDT (TRC20 / TRON):** `TLpzPs9YiUo5aJkHfGsn2FJViGYeN1mu3L`
- **Bitcoin (BTC):** `bc1qyknwc9z3uhrpnwzyz05lp2lrmqswxxwuthjg6z`
- **Solana (SOL):** `7G3dMnz12rjFiwkTDjxf713q1xDmcXPjP3xCPnAwsfe4`
