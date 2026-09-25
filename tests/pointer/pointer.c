/*
 * Inject pointer events into a Hyprland session through
 * zwlr_virtual_pointer_manager_v1, so a nest test can click and drag the way a
 * user does instead of calling the pack's functions directly.
 *
 * Hyprland turns a virtual pointer into an ordinary IPointer (see
 * CInputManager::newVirtualMouse), so a warp runs mouseMoveUnified() and emits
 * input.mouse.move, and a button press emits input.mouse.button. Those are the
 * two events hyprbars' titlebar and its drag session listen to, which is why
 * this reaches the same code a real mouse does.
 *
 * Positions are pixels in the nest's logical layout; the protocol wants them
 * normalised, so X_MODE_POINTER_EXTENT carries "WxH" (the logical monitor size)
 * and this divides before sending.
 *
 * usage:
 *   pointer move  X Y [BUTTON]
 *   pointer click X Y [BUTTON]
 *   pointer drag  X1 Y1 X2 Y2 [BUTTON]
 *   pointer button BUTTON press|release
 */

#define _GNU_SOURCE

#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct wl_display                      *display;
static struct wl_registry                     *registry;
static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct wl_seat                         *seat;
static struct zwlr_virtual_pointer_v1         *pointer;

static uint32_t                                extent_x = 1920, extent_y = 1080;
static int                                     step_ms  = 12;

static void
registry_global(void *data, struct wl_registry *reg, uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0)
        manager = wl_registry_bind(reg, name, &zwlr_virtual_pointer_manager_v1_interface, version < 2 ? version : 2);
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

static uint32_t
now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static void
settle(void) {
    wl_display_flush(display);
    wl_display_roundtrip(display);
}

/* Absolute warp. Clamped to the extent so a test with a stale window position
 * lands on the monitor instead of being rejected by the compositor. */
static void
warp(int x, int y) {
    if (x < 0)
        x = 0;
    if (y < 0)
        y = 0;
    if (x > (int)extent_x)
        x = (int)extent_x;
    if (y > (int)extent_y)
        y = (int)extent_y;

    zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), (uint32_t)x, (uint32_t)y, extent_x, extent_y);
    zwlr_virtual_pointer_v1_frame(pointer);
    settle();
}

static void
button(uint32_t code, int pressed) {
    zwlr_virtual_pointer_v1_button(pointer, now_ms(), code,
                                   pressed ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
    zwlr_virtual_pointer_v1_frame(pointer);
    settle();
}

static void
sleep_ms(int ms) {
    struct timespec ts = {.tv_sec = ms / 1000, .tv_nsec = (long)(ms % 1000) * 1000000L};
    nanosleep(&ts, NULL);
}

static void
usage(void) {
    fprintf(stderr,
            "usage: pointer move X Y [BUTTON]\n"
            "       pointer click X Y [BUTTON]\n"
            "       pointer drag X1 Y1 X2 Y2 [BUTTON]\n"
            "       pointer button BUTTON press|release\n"
            "       pointer hold\n"
            "\n"
            "hold reads commands from stdin, one per line, printing 'ok' after each:\n"
            "  move X Y | press [BUTTON] | release [BUTTON]\n"
            "  click X Y [BUTTON] | drag X1 Y1 X2 Y2 [BUTTON] | sleep MS | exit\n"
            "One process means one virtual pointer, so a button held down stays\n"
            "held while the caller does something else, which a fresh process per\n"
            "command cannot do: it would destroy the device and drop the button.\n");
    exit(2);
}

static uint32_t
parse_button(const char *s) {
    if (!s)
        return BTN_LEFT;
    if (strcmp(s, "left") == 0)
        return BTN_LEFT;
    if (strcmp(s, "right") == 0)
        return BTN_RIGHT;
    if (strcmp(s, "middle") == 0)
        return BTN_MIDDLE;
    return (uint32_t)strtoul(s, NULL, 0);
}

/* Pointer motion between two points. A drag only becomes a drag once the
 * compositor sees movement past binds:drag_threshold, and the drag session
 * positions the window from each motion event, so walk the path in steps. */
static void
drag_path(int x1, int y1, int x2, int y2) {
    const int dx    = x2 - x1;
    const int dy    = y2 - y1;
    const int dist  = abs(dx) + abs(dy);
    int       steps = dist / 6;
    if (steps < 4)
        steps = 4;
    if (steps > 60)
        steps = 60;

    for (int i = 1; i <= steps; i++) {
        warp(x1 + dx * i / steps, y1 + dy * i / steps);
        sleep_ms(step_ms);
    }
}

static void
click_at(int x, int y, uint32_t btn) {
    warp(x, y);
    sleep_ms(step_ms);
    button(btn, 1);
    sleep_ms(step_ms);
    button(btn, 0);
}

/* One command per line on stdin, 'ok' per line on stdout so the caller can
 * wait for each step. Keeps a single virtual pointer for the whole session. */
static int
hold(void) {
    char line[256];

    while (fgets(line, sizeof line, stdin)) {
        char *nl = strchr(line, '\n');
        if (nl)
            *nl = '\0';

        char *verb = strtok(line, " \t");
        if (!verb || verb[0] == '\0') {
            printf("ok\n");
            fflush(stdout);
            continue;
        }
        if (strcmp(verb, "exit") == 0)
            break;

        char *a1 = strtok(NULL, " \t");
        char *a2 = strtok(NULL, " \t");
        char *a3 = strtok(NULL, " \t");
        char *a4 = strtok(NULL, " \t");
        char *a5 = strtok(NULL, " \t");

        if (strcmp(verb, "move") == 0 && a1 && a2)
            warp(atoi(a1), atoi(a2));
        else if (strcmp(verb, "press") == 0)
            button(parse_button(a1), 1);
        else if (strcmp(verb, "release") == 0)
            button(parse_button(a1), 0);
        else if (strcmp(verb, "click") == 0 && a1 && a2)
            click_at(atoi(a1), atoi(a2), parse_button(a3));
        else if (strcmp(verb, "drag") == 0 && a1 && a2 && a3 && a4)
            {
                const uint32_t btn = parse_button(a5);
                warp(atoi(a1), atoi(a2));
                sleep_ms(step_ms);
                button(btn, 1);
                sleep_ms(step_ms);
                drag_path(atoi(a1), atoi(a2), atoi(a3), atoi(a4));
                sleep_ms(step_ms);
                button(btn, 0);
            }
        else if (strcmp(verb, "sleep") == 0 && a1)
            sleep_ms(atoi(a1));
        else
            fprintf(stderr, "pointer: unknown command '%s'\n", verb);

        printf("ok\n");
        fflush(stdout);
    }
    return 0;
}

int
main(int argc, char **argv) {
    if (argc < 2)
        usage();

    const char *extent = getenv("X_MODE_POINTER_EXTENT");
    if (extent && sscanf(extent, "%ux%u", &extent_x, &extent_y) != 2)
        fprintf(stderr, "pointer: bad X_MODE_POINTER_EXTENT '%s', using %ux%u\n", extent, extent_x, extent_y);
    const char *step = getenv("X_MODE_POINTER_STEP_MS");
    if (step)
        step_ms = atoi(step);

    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "pointer: cannot connect to WAYLAND_DISPLAY\n");
        return 1;
    }

    registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (!manager) {
        fprintf(stderr, "pointer: the compositor has no zwlr_virtual_pointer_manager_v1\n");
        return 1;
    }

    pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
    settle();

    const char *cmd = argv[1];
    int         rc  = 0;

    if (strcmp(cmd, "hold") == 0) {
        rc = hold();
    } else if (strcmp(cmd, "move") == 0) {
        if (argc < 4)
            usage();
        warp(atoi(argv[2]), atoi(argv[3]));
    } else if (strcmp(cmd, "click") == 0) {
        if (argc < 4)
            usage();
        click_at(atoi(argv[2]), atoi(argv[3]), parse_button(argc > 4 ? argv[4] : NULL));
    } else if (strcmp(cmd, "drag") == 0) {
        if (argc < 6)
            usage();
        const int      x1  = atoi(argv[2]);
        const int      y1  = atoi(argv[3]);
        const int      x2  = atoi(argv[4]);
        const int      y2  = atoi(argv[5]);
        const uint32_t btn = parse_button(argc > 6 ? argv[6] : NULL);
        warp(x1, y1);
        sleep_ms(step_ms);
        button(btn, 1);
        sleep_ms(step_ms);
        drag_path(x1, y1, x2, y2);
        sleep_ms(step_ms);
        button(btn, 0);
    } else if (strcmp(cmd, "button") == 0) {
        if (argc < 4)
            usage();
        button(parse_button(argv[2]), strcmp(argv[3], "press") == 0);
    } else {
        usage();
    }

    settle();
    zwlr_virtual_pointer_v1_destroy(pointer);
    zwlr_virtual_pointer_manager_v1_destroy(manager);
    wl_display_flush(display);
    wl_display_disconnect(display);
    return rc;
}
