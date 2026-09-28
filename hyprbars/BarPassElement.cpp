#include "BarPassElement.hpp"
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include "barDeco.hpp"

#include <algorithm>

using namespace Render::GL;

CBarPassElement::CBarPassElement(const CBarPassElement::SBarData& data_) : data(data_) {
    ;
}

std::vector<UP<IPassElement>> CBarPassElement::draw() {
    data.deco->renderPass(g_pHyprRenderer->m_renderData.pMonitor.lock(), data.a);
    return {};
}

bool CBarPassElement::needsLiveBlur() {
    static auto PENABLEBLURGLOBAL = CConfigValue<Config::BOOL>("decoration:blur:enabled");

    CHyprColor  color = data.deco->m_bForcedBarColor.value_or(CHyprColor{static_cast<uint64_t>(g_pGlobalState->config.barColor->value())});
    color.a *= data.a;
    const bool SHOULDBLUR = g_pGlobalState->config.barBlur->value() && *PENABLEBLURGLOBAL && color.a < 1.F;

    return SHOULDBLUR;
}

std::optional<CBox> CBarPassElement::boundingBox() {
    const auto PMONITOR = g_pHyprRenderer->m_renderData.pMonitor;
    if (!PMONITOR)
        return std::nullopt;

    // renderPass() paints two things: the bar strip, and the whole window box in
    // the bar color (the fill behind the window content). An element whose
    // declared box misses the frame's damage is discarded outright, so the box
    // has to cover both. With the bar's box alone, a frame that only damaged the
    // window below the bar dropped the element and everything the fill covers --
    // the band a client leaves unpainted, and the border ring, whose theme
    // colors are translucent -- flickered to whatever was behind the window.
    // It also has to cover the live-blur region the fill asks for.
    CBox barBox = data.deco->assignedBoxGlobal().translate(-PMONITOR->m_position);
    CBox winBox = data.deco->windowBoxGlobal().translate(-PMONITOR->m_position);

    CBox bb = barBox;
    if (winBox.w >= 1 && winBox.h >= 1) {
        const auto X1 = std::min(barBox.x, winBox.x);
        const auto Y1 = std::min(barBox.y, winBox.y);
        const auto X2 = std::max(barBox.x + barBox.w, winBox.x + winBox.w);
        const auto Y2 = std::max(barBox.y + barBox.h, winBox.y + winBox.h);
        bb            = CBox{X1, Y1, X2 - X1, Y2 - Y1};
    }

    // Temporary fix: expand the bar bb a bit, otherwise occlusion gets too aggressive.
    bb.expand(10);
    return bb;
}

bool CBarPassElement::needsPrecomputeBlur() {
    return false;
}
