// Keeping the visual top of a window when its chrome grows: adding a tab makes
// hyprbars draw one more row above the window box, so the content has to move down
// by that growth while the bottom edge stays put. The arithmetic is the pack's
// plugin's, not the config's: it needs the same chrome height, gap and border the
// plugin itself uses.
//
// This is the part that can be wrong without a compositor, so it is a header of
// its own and is tested with plain rectangles (tests/unit/frame_fit_test.cpp).
#pragma once

#include <algorithm>

namespace XMode {

struct SBox {
    double x = 0;
    double y = 0;
    double w = 0;
    double h = 0;
};

struct SFrameFit {
    double y = 0;
    double h = 0;
};

// old: the box before the chrome changed. usable: the monitor's usable area.
// edge: the gap plus border the window sits inside, as the plugin reports it.
inline SFrameFit fitAfterChromeGrow(const SBox& old, double oldChrome, double newChrome, const SBox& usable, double edge) {
    const double grow = std::max(newChrome - oldChrome, 0.0);

    // Put the content at the old top plus the growth, so what a person sees as the
    // top of the window does not move. Never above the first row the chrome leaves.
    double y = old.y + grow;
    const double minTop = usable.y + edge + newChrome;
    if (y < minTop)
        y = minTop;

    // Keep the bottom edge where it was: the height loses exactly the growth, and
    // then it is capped by what is left between the chrome and the usable bottom
    // edge.
    //
    // This is the arithmetic exactly as the config wrote it, limits and order
    // included. Two things follow from that and are kept on purpose, because a
    // move is not the place to change them:
    //   * the cap is applied after the floor, so a usable area smaller than the
    //     chrome leaves a height below 1 (or negative) -- the resize call then
    //     decides what to do with it;
    //   * y and h are limited independently, so a box that was already taller than
    //     the usable area keeps its bottom below it instead of moving up.
    double h = std::max(1.0, old.h - grow);
    const double maxH = usable.h - edge - edge - newChrome;
    if (h > maxH)
        h = maxH;

    return {y, h};
}

} // namespace XMode
