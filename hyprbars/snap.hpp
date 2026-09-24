#pragma once

#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <hyprland/src/helpers/math/Math.hpp>
#include <optional>
#include <string>
#include <string_view>

// Rectangle-style snap geometry. One copy of the math, used by the titlebar
// drag and by the Lua hotkeys (hl.plugin.hyprbars.snap).
namespace Snap {

    enum class eKind {
        None = 0,
        Left,
        Right,
        Top,
        Bottom,
        TopLeft,
        TopRight,
        BottomLeft,
        BottomRight,
        Maximize,
        AlmostMaximize,
    };

    eKind              kindFromString(std::string_view s);
    const char*        kindToString(eKind k);

    int                gapOut();
    int                border();
    int                chromeH(PHLWINDOW w);

    // Make gapOut() and border() report these instead of the live config, so a
    // window can be matched against the zone it held under different gaps.
    // Pass -1 to read the config again.
    void               assumeGaps(int gap, int border);

    CBox               monitorBox(PHLMONITOR mon);
    CBox               usable(PHLMONITOR mon);
    // The top usable() resolves for a monitor: the reserved top, or the last
    // non-zero one while the bar is gone for a moment (shell restart). Lua
    // clamps windows itself in a few places and needs the same number.
    double             barTop(PHLMONITOR mon);
    // Full snap zone (titlebar + tabbar + content). Preview draws this.
    std::optional<CBox> zoneBox(eKind kind, PHLMONITOR mon);
    // Content box written to the layout target (zone shifted down by chrome).
    std::optional<CBox> contentBox(eKind kind, PHLMONITOR mon, PHLWINDOW w);

    // Cursor-edge zone. `dragged` is the window being moved (may be null).
    // `activeDrag` enables the top-zone fallback when the titlebar is clamped
    // under the top bar and the cursor cannot reach the screen edge.
    eKind              zoneAtCursor(const Vector2D& cursor, PHLWINDOW dragged, bool activeDrag);

    // Place the window's layout target at the content box. Unsets fullscreen
    // and floats if needed.
    bool               applyContent(PHLWINDOW w, const CBox& content);
    bool               applyKind(PHLWINDOW w, eKind kind);

    // The zone a window currently occupies, or None. Compared in the same
    // logical pixels applyKind writes, so a window snapped by the plugin is
    // recognised again. `slop` absorbs the one pixel a layout round can move.
    eKind              kindOf(PHLWINDOW w, int slop = 2);

    // Titlebar-drag move: compositor-only (no client configure), position
    // warped so chrome and the surface share the same pixel this frame.
    void               moveDrag(PHLWINDOW w, Vector2D pos);

}
