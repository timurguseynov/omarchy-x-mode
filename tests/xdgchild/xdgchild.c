/*
 * Open a Wayland toplevel with a child toplevel that has it as its xdg parent,
 * so a nest scenario can look at what the pack does with a dialog of the kind
 * Geary opens: floated (Hyprland floats a toplevel with a parent) and refused a
 * tab (hyprbars.groupable), it is a separate floating window of the same app.
 *
 * usage: xdgchild PARENT_CLASS CHILD_CLASS
 *
 * Two toplevels of one connection, each with the given app id, and the child
 * carries xdg_toplevel.set_parent. Both are mapped with a plain shm buffer so
 * Hyprland has a window with a box to raise. The process stays up and dispatches
 * until the nest closes, so the windows live as long as the scenario needs them.
 *
 * set_parent, not modal: modal comes from the separate xdg-dialog-v1 protocol
 * (xdg_wm_dialog_v1), and the pack turns Hyprland's modal blocking off anyway --
 * what this test needs is the parent link Hyprland floats and CWindow::parent()
 * reports.
 *
 * X11 would not do: Hyprland's CWindowState::moveToZ already lifts an X11
 * transient stack when it raises a window, so an X11 dialog would be above its
 * parent with or without the pack. Only a Wayland toplevel exercises the raise
 * path this is here to check.
 */

#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/mman.h>

#include <wayland-client.h>

#include "xdg-shell-client-protocol.h"

static struct wl_display    *display;
static struct wl_compositor *compositor;
static struct wl_shm        *shm;
static struct xdg_wm_base   *wm_base;

struct window {
    struct wl_surface   *surface;
    struct xdg_surface  *xdg_surface;
    struct xdg_toplevel *toplevel;
    const char          *cls;
    int                  configured;
};

static void
xdg_wm_base_ping(void *data, struct xdg_wm_base *base, uint32_t serial) {
    (void)data;
    xdg_wm_base_pong(base, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {
    .ping = xdg_wm_base_ping,
};

static void
registry_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, wl_compositor_interface.name) == 0)
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    else if (strcmp(interface, wl_shm_interface.name) == 0)
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
        wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);
    }
}

static void
registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global        = registry_global,
    .global_remove = registry_global_remove,
};

static void
xdg_surface_configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial) {
    struct window *w = data;
    xdg_surface_ack_configure(xdg_surface, serial);
    w->configured = 1;
}

static const struct xdg_surface_listener xdg_surface_listener = {
    .configure = xdg_surface_configure,
};

static void
toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t width, int32_t height, struct wl_array *states) {
    (void)data;
    (void)toplevel;
    (void)width;
    (void)height;
    (void)states;
}

static void
toplevel_close(void *data, struct xdg_toplevel *toplevel) {
    (void)data;
    (void)toplevel;
    exit(0);
}

static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = toplevel_configure,
    .close     = toplevel_close,
};

static struct wl_buffer *
make_buffer(int width, int height, uint32_t color) {
    const int stride = width * 4;
    const int size   = stride * height;

    int       fd     = memfd_create("xmode-xdgchild", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, size) < 0)
        return NULL;

    uint32_t *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED) {
        close(fd);
        return NULL;
    }
    for (int i = 0; i < width * height; i++)
        pixels[i] = color;
    munmap(pixels, size);

    struct wl_shm_pool *pool   = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer   *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return buffer;
}

static struct window *
make_window(const char *cls, const char *title) {
    struct window *w = calloc(1, sizeof(*w));
    if (w == NULL)
        return NULL;

    w->cls       = cls;
    w->surface   = wl_compositor_create_surface(compositor);
    w->xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, w->surface);
    xdg_surface_add_listener(w->xdg_surface, &xdg_surface_listener, w);
    w->toplevel = xdg_surface_get_toplevel(w->xdg_surface);
    xdg_toplevel_add_listener(w->toplevel, &toplevel_listener, w);
    xdg_toplevel_set_app_id(w->toplevel, cls);
    xdg_toplevel_set_title(w->toplevel, title);
    return w;
}

/* The first commit starts the configure dance; the buffer goes on after the
 * configure has been acked, which is the point Hyprland maps the window. */
static void
map_window(struct window *w, int width, int height, uint32_t color) {
    while (!w->configured)
        wl_display_dispatch(display);

    struct wl_buffer *buffer = make_buffer(width, height, color);
    if (buffer == NULL) {
        fprintf(stderr, "xdgchild: no shm buffer\n");
        exit(1);
    }
    wl_surface_attach(w->surface, buffer, 0, 0);
    wl_surface_damage_buffer(w->surface, 0, 0, width, height);
    wl_surface_commit(w->surface);
}

int
main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: xdgchild PARENT_CLASS CHILD_CLASS\n");
        return 2;
    }

    display = wl_display_connect(NULL);
    if (display == NULL) {
        fprintf(stderr, "xdgchild: no display\n");
        return 1;
    }

    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (compositor == NULL || shm == NULL || wm_base == NULL) {
        fprintf(stderr, "xdgchild: compositor, shm or xdg_wm_base missing\n");
        return 1;
    }

    struct window *parent = make_window(argv[1], "x-mode dialog parent");
    struct window *child  = make_window(argv[2], "x-mode dialog child");
    if (parent == NULL || child == NULL)
        return 1;

    /* Before either surface's first commit, so the server knows the parent when
     * it applies the child's initial state. */
    xdg_toplevel_set_parent(child->toplevel, parent->toplevel);

    wl_surface_commit(parent->surface);
    wl_surface_commit(child->surface);

    map_window(parent, 520, 420, 0x00204060);
    map_window(child, 320, 220, 0x00602020);
    wl_display_roundtrip(display);

    while (wl_display_dispatch(display) != -1) {
    }
    return 0;
}
