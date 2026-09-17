# X Mode for Omarchy

A macOS-like desktop layer for [Omarchy](https://omarchy.org) — floating windows, app tabs, Rectangle-style window snapping, a right-edge dock, and macOS application switcher.

https://github.com/user-attachments/assets/f4b7c208-6e6c-4880-a805-128d79c872e7

It is **100% additive**. The installer never overwrites your existing setup or custom configs. Uninstalling cleanly removes only what was added.

**Floating windows · Mac titlebars · App tabs · Window snapping · Dock · App switcher**

> Optional profile. Default Omarchy tiling stays the default until you toggle X Mode on.

---

## Key Features

* **Floating Desktop** — Windows open floating by default with rounded corners and drop shadows. Move and resize naturally without wrestling with tiling layouts.
* **Mac Titlebars & Window Tabs** — Clean window headers with native controls. Windows of the same application automatically group into manageable tabs.
* **Rectangle-Style Snapping** — Drag windows to screen edges with live visual feedback, or use keyboard shortcuts (including `½ → ⅔ → ⅓` width cycling on left/right edges).
* **Right-Edge Dock** — Access running and pinned applications quickly. Includes window-overlay support, launch/focus actions, and context menus for app management.
* **App Switcher (`Super+Tab`)** — Centered macOS-style switcher for smooth cycling between active applications.
* **Quick Configuration Panel** — Access X Mode settings directly from the top bar:
  * Toggle X Mode globally on or off
  * Natural (reversed) touchpad scrolling
  * Per-app window chrome and tab grouping toggles
  * Always show tab bar option

---

## Keyboard Shortcuts

> `Super` represents your primary modifier key (Windows / Command).

### Window & Tab Management

| Shortcut | Action |
| --- | --- |
| `Super` + `Tab` | Switch to next application |
| `Super` + `Shift` + `Tab` | Switch to previous application |
| `Alt` + `Tab` | Switch to next tab in focused group |
| `Alt` + `Shift` + `Tab` | Switch to previous tab in focused group |
| `Ctrl` + `1`…`9` | Jump directly to tab *N* |
| `Super` + `W` | Close active window or tab |
| `Super` + `Q` | Quit active application (closes all tabs) |
| `Super` + `←` / `→` | Focus window to the left / right |

### Window Snapping

| Shortcut | Action |
| --- | --- |
| `Super` + `Alt` + `←` / `→` | Snap Left / Right (cycles `½ → ⅔ → ⅓`) |
| `Super` + `Alt` + `F` | Maximize window |
| `Super` + `Alt` + `A` | Almost-maximize (inset from screen edges) |
| `Ctrl` + `Alt` + `↑` | Maximize window |
| `Ctrl` + `Alt` + `↓` | Restore previous size |
| `Ctrl` + `Alt` + `U` / `I` | Top-Left / Top-Right quarter |
| `Ctrl` + `Alt` + `J` / `K` | Bottom-Left / Bottom-Right quarter |

### Mouse Gestures

| Action | Result |
| --- | --- |
| Drag titlebar to edge | Snap window (with visual live preview) |
| Drag titlebar to top-center | Maximize window |
| Left-click dock icon | Focus or launch application |
| Right-click dock icon | Pin/unpin, reorder, or quit application |

---

## Installation

Run the automated installer:

```bash
git clone https://github.com/timurguseynov/omarchy-x-mode.git ~/omarchy-x-mode
~/omarchy-x-mode/install.sh
```

If the desktop environment doesn't refresh automatically, apply changes with:

```bash
hyprctl reload
omarchy-restart-shell
```

---

## Uninstallation

To completely remove X Mode and restore your system settings:

```bash
~/omarchy-x-mode/uninstall.sh
```

This safely removes all installed components while keeping your personal configurations completely untouched.

---

## License

Distributed under the MIT License. See `LICENSE` for details.
