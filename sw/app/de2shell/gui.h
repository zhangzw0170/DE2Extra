/* gui.h — Lightweight static GUI widget toolkit
 *
 * No heap — all widgets from a static pool (max GUI_MAX_WIDGETS).
 * Z-order: linked list, bottom to top.
 * Keyboard-driven: Tab cycles focus, Enter activates.
 */
#ifndef GUI_H
#define GUI_H

#include <stdint.h>
#include "fb_hal.h"

/* ── Limits ─────────────────────────────────────────────────────── */

#define GUI_MAX_WIDGETS 32
#define GUI_TEXTINPUT_MAX 64

/* ── Widget types ───────────────────────────────────────────────── */

typedef enum {
    WIDGET_NONE = 0,
    WIDGET_WINDOW,
    WIDGET_BUTTON,
    WIDGET_LABEL,
    WIDGET_TEXTINPUT,
    WIDGET_TASKBAR,
    WIDGET_ICON
} widget_type_t;

/* ── Keyboard event ─────────────────────────────────────────────── */

typedef struct {
    uint8_t ascii;
    uint8_t scancode;
    uint8_t is_press;
    uint8_t is_extended;
} gui_event_t;

/* ── Forward declaration ────────────────────────────────────────── */

struct widget;
typedef struct widget widget_t;

/* ── Widget callbacks ───────────────────────────────────────────── */

typedef void (*widget_render_fn)(widget_t *self);
typedef int  (*widget_key_fn)(widget_t *self, const gui_event_t *ev);

/* ── Widget struct ──────────────────────────────────────────────── */

struct widget {
    widget_type_t  type;
    int            x, y, w, h;
    int            visible;
    int            focused;
    int            pressed;       /* button/visual feedback */
    int            active;        /* window: title bar highlighted */
    const char    *text;          /* label, button caption, window title */
    char           textbuf[GUI_TEXTINPUT_MAX]; /* textinput buffer */
    int            textpos;       /* cursor position in textbuf */
    int            textlen;       /* current text length */
    widget_t      *parent;
    widget_t      *next;          /* z-order linked list */
    widget_t      *children;      /* first child */
    widget_render_fn render;
    widget_key_fn    key;
    /* icon-specific */
    const uint8_t  *icon_bitmap;  /* 32x32 or NULL */
};

/* ── Public API ─────────────────────────────────────────────────── */

void gui_init(void);

/* Allocate a widget from the pool. Returns NULL if pool exhausted. */
widget_t *gui_create(widget_type_t type, int x, int y, int w, int h,
                     const char *text, widget_t *parent);

/* Remove widget (and children) from the scene. */
void gui_destroy(widget_t *w);

/* Render all visible widgets bottom-to-top. */
void gui_render_all(void);

/* Send a keyboard event to the focused widget.
 * Returns 1 if the event was consumed, 0 if not. */
int gui_dispatch_key(const gui_event_t *ev);

/* Move focus to next/prev focusable widget. */
void gui_focus_next(void);
void gui_focus_prev(void);

/* Bring widget to top of z-order. */
void gui_raise(widget_t *w);

/* Find widget at pixel coordinates (for future mouse/touch). */
widget_t *gui_widget_at(int x, int y);

/* Assign render/key callbacks based on widget type. Called by gui_create. */
void gui_widget_setup(widget_t *w);

#endif /* GUI_H */
