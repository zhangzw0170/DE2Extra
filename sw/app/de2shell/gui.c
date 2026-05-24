/* gui.c — Static GUI widget manager */
#include "gui.h"
#include "gfx.h"
#include <string.h>

/* ── Widget pool ────────────────────────────────────────────────── */

static widget_t pool[GUI_MAX_WIDGETS];
static widget_t *z_order;   /* linked list: bottom → top */
static widget_t *focused;   /* currently focused widget */

/* ── Init ───────────────────────────────────────────────────────── */

void gui_init(void) {
    memset(pool, 0, sizeof(pool));
    z_order = NULL;
    focused = NULL;
    for (int i = 0; i < GUI_MAX_WIDGETS; i++)
        pool[i].type = WIDGET_NONE;
}

/* ── Allocation ─────────────────────────────────────────────────── */

widget_t *gui_create(widget_type_t type, int x, int y, int w, int h,
                     const char *text, widget_t *parent) {
    widget_t *slot = NULL;
    for (int i = 0; i < GUI_MAX_WIDGETS; i++) {
        if (pool[i].type == WIDGET_NONE) { slot = &pool[i]; break; }
    }
    if (!slot) return NULL;

    memset(slot, 0, sizeof(widget_t));
    slot->type     = type;
    slot->x        = x;
    slot->y        = y;
    slot->w        = w;
    slot->h        = h;
    slot->text     = text;
    slot->parent   = parent;
    slot->visible  = 1;
    slot->active   = 1;

    /* Assign render/key callbacks */
    gui_widget_setup(slot);

    /* Append to z-order list (top) */
    if (!z_order) {
        z_order = slot;
    } else {
        widget_t *p = z_order;
        while (p->next) p = p->next;
        p->next = slot;
    }

    /* Add to parent's children list */
    if (parent) {
        if (!parent->children) {
            parent->children = slot;
        } else {
            widget_t *c = parent->children;
            while (c->next) c = c->next;
            /* Unlink from main z-order — children render with parent */
            /* For simplicity, children stay in z-order but are skipped
             * during render_all if they have a parent. The parent's
             * render function draws its children explicitly. */
        }
    }

    return slot;
}

/* ── Destruction ────────────────────────────────────────────────── */

static void unlink_widget(widget_t *w) {
    if (z_order == w) {
        z_order = w->next;
    } else {
        widget_t *p = z_order;
        while (p && p->next != w) p = p->next;
        if (p) p->next = w->next;
    }
    w->next = NULL;
}

void gui_destroy(widget_t *w) {
    if (!w) return;
    /* Destroy children first */
    widget_t *c = w->children;
    while (c) {
        widget_t *next = c->next;
        gui_destroy(c);
        c = next;
    }
    /* Remove from parent's children */
    if (w->parent && w->parent->children == w) {
        w->parent->children = w->next;
    }
    /* Unlink from z-order */
    unlink_widget(w);
    if (focused == w) focused = NULL;
    w->type = WIDGET_NONE;
}

/* ── Render ─────────────────────────────────────────────────────── */

void gui_render_all(void) {
    widget_t *w = z_order;
    while (w) {
        /* Skip children — they're rendered by their parent */
        if (w->visible && !w->parent && w->render) {
            w->render(w);
        }
        w = w->next;
    }
}

/* ── Focus ──────────────────────────────────────────────────────── */

static int is_focusable(widget_t *w) {
    if (!w || !w->visible) return 0;
    return (w->type == WIDGET_BUTTON || w->type == WIDGET_TEXTINPUT ||
            w->type == WIDGET_WINDOW || w->type == WIDGET_ICON);
}

void gui_focus_next(void) {
    if (!z_order) return;
    widget_t *start = focused ? focused->next : z_order;
    widget_t *w = start;
    do {
        if (!w) w = z_order;
        if (is_focusable(w)) {
            if (focused) focused->focused = 0;
            focused = w;
            w->focused = 1;
            return;
        }
        w = w->next;
    } while (w != start);

    /* Wrap: try from head */
    w = z_order;
    while (w && w != start) {
        if (is_focusable(w)) {
            if (focused) focused->focused = 0;
            focused = w;
            w->focused = 1;
            return;
        }
        w = w->next;
    }
}

void gui_focus_prev(void) {
    /* Walk list to find predecessor of focused */
    if (!z_order) return;
    if (!focused) { gui_focus_next(); return; }

    /* Collect focusable widgets into a small array for reverse walk */
    widget_t *focusable[GUI_MAX_WIDGETS];
    int count = 0;
    widget_t *w = z_order;
    while (w) {
        if (is_focusable(w)) focusable[count++] = w;
        w = w->next;
    }
    if (count == 0) return;

    int idx = -1;
    for (int i = 0; i < count; i++) {
        if (focusable[i] == focused) { idx = i; break; }
    }
    int prev = (idx > 0) ? idx - 1 : count - 1;
    focused->focused = 0;
    focused = focusable[prev];
    focused->focused = 1;
}

/* ── Key dispatch ───────────────────────────────────────────────── */

int gui_dispatch_key(const gui_event_t *ev) {
    if (!focused || !focused->key) return 0;
    return focused->key(focused, ev);
}

/* ── Raise to top ───────────────────────────────────────────────── */

void gui_raise(widget_t *w) {
    if (!w || z_order == w) return;
    unlink_widget(w);
    /* Append to end */
    widget_t *p = z_order;
    while (p->next) p = p->next;
    p->next = w;
    w->next = NULL;
}

/* ── Hit test ───────────────────────────────────────────────────── */

widget_t *gui_widget_at(int x, int y) {
    /* Walk z-order in reverse (top first) */
    widget_t *hit = NULL;
    widget_t *w = z_order;
    while (w) {
        if (w->visible && !w->parent &&
            x >= w->x && x < w->x + w->w &&
            y >= w->y && y < w->y + w->h) {
            hit = w;
        }
        w = w->next;
    }
    return hit;
}
