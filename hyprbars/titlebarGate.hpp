#pragma once

#include "globals.hpp"

#include <hyprland/src/desktop/view/Window.hpp>

// Which titlebar a window gets. The pack's tag and Omarchy's floating-workspace
// tag are both gates: either one draws a bar, and a window that carries the
// pack's tag keeps the pack's look even if it also carries hers. An empty pack
// tag draws the pack's bar everywhere, which is what a stock hyprbars does.

inline bool windowHasTag(PHLWINDOW w, const std::string& tag) {
    if (!w || tag.empty() || !w->m_ruleApplicator)
        return false;

    for (const auto& have : w->m_ruleApplicator->m_tagKeeper.getTags()) {
        if (have == tag || have == tag + "*")
            return true;
    }

    return false;
}

inline bool packTitlebarWindow(PHLWINDOW w) {
    if (!g_pGlobalState || !g_pGlobalState->config.xModeWorkspaceTag)
        return true;

    const auto tag = g_pGlobalState->config.xModeWorkspaceTag->value();
    if (tag.empty())
        return true;

    return windowHasTag(w, tag);
}

inline bool omarchyTitlebarWindow(PHLWINDOW w) {
    if (!g_pGlobalState || !g_pGlobalState->omarchy.set || packTitlebarWindow(w))
        return false;
    if (!g_pGlobalState->config.omarchyWorkspaceTag)
        return false;

    return windowHasTag(w, g_pGlobalState->config.omarchyWorkspaceTag->value());
}

inline bool wantsTitlebarWindow(PHLWINDOW w) {
    if (packTitlebarWindow(w))
        return true;
    if (!g_pGlobalState || !g_pGlobalState->config.omarchyWorkspaceTag)
        return false;

    const auto tag = g_pGlobalState->config.omarchyWorkspaceTag->value();
    if (tag.empty())
        return false;

    return windowHasTag(w, tag);
}

inline int titlebarHeight(PHLWINDOW w) {
    if (!g_pGlobalState || !g_pGlobalState->config.barHeight)
        return 0;
    if (omarchyTitlebarWindow(w))
        return g_pGlobalState->omarchy.height;

    return g_pGlobalState->config.barHeight->value();
}

inline std::vector<SHyprButton>& titlebarButtons(PHLWINDOW w) {
    if (omarchyTitlebarWindow(w))
        return g_pGlobalState->omarchyButtons;

    return g_pGlobalState->buttons;
}

inline int titlebarPadding(PHLWINDOW w) {
    if (omarchyTitlebarWindow(w))
        return g_pGlobalState->omarchy.padding;

    return g_pGlobalState->config.barPadding->value();
}

inline int titlebarButtonPadding(PHLWINDOW w) {
    if (omarchyTitlebarWindow(w))
        return g_pGlobalState->omarchy.buttonPadding;

    return g_pGlobalState->config.barButtonPadding->value();
}

inline std::string titlebarButtonsAlign(PHLWINDOW w) {
    if (omarchyTitlebarWindow(w))
        return g_pGlobalState->omarchy.buttonsAlign;

    return g_pGlobalState->config.barButtonsAlignment->value();
}

inline std::string titlebarTextAlign(PHLWINDOW w) {
    if (omarchyTitlebarWindow(w))
        return g_pGlobalState->omarchy.textAlign;

    return g_pGlobalState->config.barTextAlign->value();
}

inline std::string titlebarDoubleClick(PHLWINDOW w) {
    if (omarchyTitlebarWindow(w))
        return g_pGlobalState->omarchy.onDoubleClick;

    return g_pGlobalState->config.onDoubleClick->value();
}

inline CHyprColor titlebarBarColor(PHLWINDOW w) {
    if (omarchyTitlebarWindow(w))
        return g_pGlobalState->omarchy.barColor;

    return CHyprColor{static_cast<uint64_t>(g_pGlobalState->config.barColor->value())};
}

inline CHyprColor titlebarTextColor(PHLWINDOW w) {
    if (omarchyTitlebarWindow(w))
        return g_pGlobalState->omarchy.textColor;

    return CHyprColor{static_cast<uint64_t>(g_pGlobalState->config.textColor->value())};
}
