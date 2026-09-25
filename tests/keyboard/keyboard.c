/*
 * Press key combinations in a Hyprland session through
 * zwp_virtual_keyboard_manager_v1, so a nest test can drive the pack's
 * keybindings.
 *
 * Why not wtype: Hyprland's CKeybindManager::onKeyEvent resolves the pressed key
 * through its own keymap (m_xkbTranslationState), while a client gets its keysym
 * from the device's keymap. wtype sends a synthetic keymap of its own with its own
 * keycode numbering, so the two disagree and no bind ever matches — typing into a
 * client works, keybinds do not.
 *
 * So this sends the keymap xkbcommon builds from the system rules (pc105/us), the
 * same layout Hyprland resolves against, and presses keys with libinput-style
 * codes: Hyprland does `keycode + 8` before the xkb lookup, which lands on the
 * standard XKB keycode only when the client sends the evdev code. The modifier
 * mask comes from an xkb state built on that keymap, so Mod4 really is 64 here.
 *
 * usage: keyboard [-d MS] COMBO...
 *   COMBO is a '+'-separated chord, e.g. super+alt+left, alt+tab, o.
 */

#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

#include <sys/mman.h>

#include "virtual-keyboard-unstable-v1-client-protocol.h"

#define MAX_TOKENS 16

static struct wl_display                      *display;
static struct wl_registry                     *registry;
static struct zwp_virtual_keyboard_manager_v1 *manager;
static struct wl_seat                         *seat;
static struct zwp_virtual_keyboard_v1         *keyboard;

static struct xkb_context *xkb_ctx;
static struct xkb_keymap  *xkb_map;
static struct xkb_state   *xkb_st;

static int                 delay_ms = 15;

static void
registry_global(void *data, struct wl_registry *reg, uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    if (strcmp(interface, zwp_virtual_keyboard_manager_v1_interface.name) == 0)
        manager = wl_registry_bind(reg, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
    else if (strcmp(interface, wl_seat_interface.name) == 0)
        seat = wl_registry_bind(reg, name, &wl_seat_interface, version < 5 ? version : 5);
}

static void
registry_global_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data;
    (void)reg;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global        = registry_global,
    .global_remove = registry_global_remove,
};

static void
sleep_ms(int ms) {
    struct timespec ts = {.tv_sec = ms / 1000, .tv_nsec = (long)(ms % 1000) * 1000000L};
    nanosleep(&ts, NULL);
}

static void
settle(void) {
    wl_display_flush(display);
    wl_display_roundtrip(display);
}

static uint32_t
now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

/* The keymap text goes over as an fd. */
static void
send_keymap(void) {
    char *text = xkb_keymap_get_as_string(xkb_map, XKB_KEYMAP_FORMAT_TEXT_V1);
    if (!text) {
        fprintf(stderr, "keyboard: could not serialise the keymap\n");
        exit(1);
    }
    const size_t len = strlen(text) + 1;
    const int    fd  = memfd_create("x-mode-keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, text, len) != (ssize_t)len) {
        fprintf(stderr, "keyboard: could not write the keymap\n");
        exit(1);
    }
    free(text);
    zwp_virtual_keyboard_v1_keymap(keyboard, XKB_KEYMAP_FORMAT_TEXT_V1, fd, (uint32_t)len);
    close(fd);
    settle();
}

/* xkbcommon wants the keycode with the +8 libinput offset, the compositor wants
 * the evdev one: it adds the 8 itself. The code is found by looking for the key
 * that produces the wanted symbol, so the caller only names symbols. */
static uint32_t
evdev_code(xkb_keysym_t sym) {
    const xkb_keycode_t min = xkb_keymap_min_keycode(xkb_map);
    const xkb_keycode_t max = xkb_keymap_max_keycode(xkb_map);

    for (xkb_keycode_t code = min; code <= max; code++) {
        const xkb_keysym_t *syms = NULL;
        const int           n    = xkb_keymap_key_get_syms_by_level(xkb_map, code, 0, 0, &syms);
        if (n > 0 && syms && syms[0] == sym)
            return (uint32_t)code - 8;
    }
    fprintf(stderr, "keyboard: no key produces that symbol on this layout\n");
    exit(1);
}

static void
send_mods(void) {
    zwp_virtual_keyboard_v1_modifiers(keyboard, xkb_state_serialize_mods(xkb_st, XKB_STATE_MODS_DEPRESSED),
                                      xkb_state_serialize_mods(xkb_st, XKB_STATE_MODS_LATCHED),
                                      xkb_state_serialize_mods(xkb_st, XKB_STATE_MODS_LOCKED),
                                      xkb_state_serialize_layout(xkb_st, XKB_STATE_LAYOUT_EFFECTIVE));
    settle();
}

static void
key_state(xkb_keysym_t sym, int pressed) {
    const uint32_t code = evdev_code(sym);
    zwp_virtual_keyboard_v1_key(keyboard, now_ms(), code, pressed ? 1 : 0);
    xkb_state_update_key(xkb_st, code + 8, pressed ? XKB_KEY_DOWN : XKB_KEY_UP);
    send_mods();
    sleep_ms(delay_ms);
}

static xkb_keysym_t
sym_for(const char *token) {
    static const struct {
        const char  *name;
        xkb_keysym_t sym;
    } MODS[] = {
        {"super", XKB_KEY_Super_L}, {"logo", XKB_KEY_Super_L},   {"cmd", XKB_KEY_Super_L},
        {"win", XKB_KEY_Super_L},   {"alt", XKB_KEY_Alt_L},      {"ctrl", XKB_KEY_Control_L},
        {"control", XKB_KEY_Control_L}, {"shift", XKB_KEY_Shift_L},
    };
    for (size_t i = 0; i < sizeof(MODS) / sizeof(MODS[0]); i++) {
        if (strcasecmp(token, MODS[i].name) == 0)
            return MODS[i].sym;
    }
    const xkb_keysym_t sym = xkb_keysym_from_name(token, XKB_KEYSYM_CASE_INSENSITIVE);
    if (sym == XKB_KEY_NoSymbol) {
        fprintf(stderr, "keyboard: unknown key '%s'\n", token);
        exit(2);
    }
    return sym;
}

/* Press the whole chord, then release it in reverse, so the modifier masks go
 * out around the key: Hyprland's bind matching reads them from there. */
static void
chord(const char *combo) {
    char   buf[256];
    char  *tokens[MAX_TOKENS];
    size_t n = 0;

    snprintf(buf, sizeof buf, "%s", combo);
    for (char *t = strtok(buf, "+"); t && n < MAX_TOKENS; t = strtok(NULL, "+"))
        tokens[n++] = t;
    if (n == 0)
        return;

    for (size_t i = 0; i + 1 < n; i++)
        key_state(sym_for(tokens[i]), 1);
    key_state(sym_for(tokens[n - 1]), 1);
    key_state(sym_for(tokens[n - 1]), 0);
    for (size_t i = n - 1; i-- > 0;)
        key_state(sym_for(tokens[i]), 0);
}

int
main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: keyboard [-d MS] COMBO...\n");
        return 2;
    }

    int i = 1;
    if (strcmp(argv[i], "-d") == 0 && argc > i + 1) {
        delay_ms = atoi(argv[i + 1]);
        i += 2;
    }

    xkb_ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names = {.rules = NULL, .model = "pc105", .layout = "us", .variant = NULL, .options = NULL};
    xkb_map                     = xkb_keymap_new_from_names(xkb_ctx, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (!xkb_ctx || !xkb_map) {
        fprintf(stderr, "keyboard: could not build a us keymap\n");
        return 1;
    }
    xkb_st = xkb_state_new(xkb_map);

    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "keyboard: cannot connect to WAYLAND_DISPLAY\n");
        return 1;
    }
    registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!manager) {
        fprintf(stderr, "keyboard: the compositor has no zwp_virtual_keyboard_manager_v1\n");
        return 1;
    }

    keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager, seat);
    settle();
    send_keymap();

    for (; i < argc; i++)
        chord(argv[i]);

    settle();
    zwp_virtual_keyboard_v1_destroy(keyboard);
    zwp_virtual_keyboard_manager_v1_destroy(manager);
    wl_display_flush(display);
    wl_display_disconnect(display);
    return 0;
}
