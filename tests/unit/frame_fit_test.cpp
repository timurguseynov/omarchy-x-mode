// The chrome-growth arithmetic on its own: no compositor, no plugin, just boxes.
// These are the rules the config used to spell out in Lua, and the cases that made
// them necessary are the cases tested here.
#include "hyprbars/frameFit.hpp"

#include <cmath>
#include <cstdio>

using XMode::SBox;
using XMode::SFrameFit;

namespace {

int failures = 0;

void check(const char* name, bool ok, const char* detail) {
    if (ok)
        return;
    std::fprintf(stderr, "FAIL %s: %s\n", name, detail);
    ++failures;
}

void checkNum(const char* name, double got, double want) {
    char detail[128];
    std::snprintf(detail, sizeof detail, "got %g, want %g", got, want);
    check(name, std::abs(got - want) < 0.001, detail);
}

// A window inside a 1920x1080 monitor whose usable area starts at y=30 (the bar).
const SBox usable{0, 30, 1920, 1050};

} // namespace

int main() {
    // No growth: the box is left exactly as it was.
    {
        const SFrameFit fit = XMode::fitAfterChromeGrow({100, 200, 800, 600}, 30, 30, usable, 12);
        checkNum("same.y", fit.y, 200);
        checkNum("same.h", fit.h, 600);
    }

    // One more tab row (30px taller chrome): the content moves down by 30 and the
    // height loses 30, so the bottom edge does not move.
    {
        const SFrameFit fit = XMode::fitAfterChromeGrow({100, 200, 800, 600}, 30, 60, usable, 12);
        checkNum("grow.y", fit.y, 230);
        checkNum("grow.h", fit.h, 570);
        checkNum("grow.bottom", fit.y + fit.h, 800);
    }

    // Chrome that shrank does not pull the window up: growth is never negative.
    {
        const SFrameFit fit = XMode::fitAfterChromeGrow({100, 200, 800, 600}, 60, 30, usable, 12);
        checkNum("shrink.y", fit.y, 200);
        checkNum("shrink.h", fit.h, 600);
    }

    // The growth would push the content above the first row the chrome leaves: it
    // is clamped to that row instead of sliding under the bar.
    {
        const SFrameFit fit = XMode::fitAfterChromeGrow({100, 20, 800, 600}, 0, 60, usable, 12);
        checkNum("clamp-top.y", fit.y, 30 + 12 + 60);
        checkNum("clamp-top.h", fit.h, 540);
    }

    // A tall window cannot keep its bottom edge and stay inside the monitor: the
    // height is capped by what is left below the chrome. The top is not moved up
    // for it, so the bottom may still land below the usable area -- that is the
    // behaviour the config had, pinned here so a change to it is deliberate.
    {
        const SFrameFit fit = XMode::fitAfterChromeGrow({100, 100, 800, 1000}, 30, 60, usable, 12);
        checkNum("cap-top.y", fit.y, 130);
        checkNum("cap-top.h", fit.h, 1050 - 12 - 12 - 60);
        // Documented consequence, not a promise: 130 + 966 lands below 30 + 1050.
        checkNum("cap-top.bottom", fit.y + fit.h, 1096);
    }

    // The floor is applied before the cap, exactly as the config had it: a usable
    // area smaller than the chrome leaves the capped value, even below one. Pinned
    // so that changing it is a deliberate separate decision.
    {
        const SBox tiny{0, 0, 800, 50};
        const SFrameFit fit = XMode::fitAfterChromeGrow({100, 0, 400, 100}, 0, 60, tiny, 12);
        checkNum("below-one.h", fit.h, 50 - 12 - 12 - 60);
    }

    // The height never collapses to nothing while the usable area still has room:
    // the floor keeps it at one.
    {
        const SFrameFit fit = XMode::fitAfterChromeGrow({100, 200, 800, 40}, 0, 200, usable, 12);
        check("collapse.h", fit.h >= 1.0, "height fell below 1");
    }

    // A No gaps workspace reports the workspace's own edge, which is the border (1)
    // and not 0: the fit is measured with that, not with the desktop's gap.
    {
        const SFrameFit fit = XMode::fitAfterChromeGrow({100, 100, 800, 600}, 30, 60, usable, 1);
        checkNum("border-edge.y", fit.y, 130);
        checkNum("border-edge.h", fit.h, 570);
        const SFrameFit tall = XMode::fitAfterChromeGrow({100, 100, 800, 1100}, 30, 60, usable, 1);
        checkNum("border-edge.cap", tall.h, 1050 - 1 - 1 - 60);
    }

    // A zero-gap workspace: the edge is 0, so the fit is measured against the usable
    // area itself.
    {
        const SFrameFit fit = XMode::fitAfterChromeGrow({100, 100, 800, 600}, 30, 60, usable, 0);
        checkNum("zero-edge.y", fit.y, 130);
        checkNum("zero-edge.h", fit.h, 570);
    }

    if (failures > 0) {
        std::fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    std::printf("frame fit ok\n");
    return 0;
}
