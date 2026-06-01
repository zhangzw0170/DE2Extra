/* gui.h — Tiling window manager (i3wm/sway style)
 *
 * Binary tree of containers: SPLIT_H, SPLIT_V, or LEAF.
 * No heap — static pool. Keyboard-driven, no mouse.
 *
 * Key bindings (Alt as Mod):
 *   Alt+H          Split focused leaf horizontally (side by side)
 *   Alt+V          Split focused leaf vertically (top and bottom)
 *   Alt+Arrow      Move focus to adjacent leaf
 *   Alt+W          Close focused leaf
 *   Esc            Exit desktop
 */
#ifndef GUI_H
#define GUI_H

#include <stdint.h>
#include "fb_hal.h"

/* ── Limits ─────────────────────────────────────────────────────── */

#define TILE_MAX       16
#define TILE_TITLE_MAX 24

/* ── Node types ─────────────────────────────────────────────────── */

#define TILE_LEAF    0
#define TILE_SPLIT_H 1
#define TILE_SPLIT_V 2

/* ── Tile node ──────────────────────────────────────────────────── */

typedef struct tile {
    int         type;
    struct tile *parent;
    struct tile *child[2];
    float       ratio;          /* child[0]'s share */

    /* Leaf fields */
    char  title[TILE_TITLE_MAX];
    int   id;
    int   focused;
    int   active;

    /* Computed rect (set by tile_layout) */
    int   x, y, w, h;
} tile_t;

/* ── Public API ─────────────────────────────────────────────────── */

void     tile_init(void);
tile_t  *tile_split(int dir);       /* 0=H, 1=V. Returns new leaf. */
void     tile_close(void);
void     tile_focus_dir(int dir);   /* 0=left, 1=right, 2=up, 3=down */
tile_t  *tile_focused(void);
tile_t  *tile_root(void);
void     tile_layout(void);
void     tile_render_all(void);

/* Resize: axis 0=H(left/right) 1=V(up/down), sign +1/-1 */
void     tile_resize(int axis, int sign);

/* Fullscreen toggle for focused leaf */
void     tile_toggle_fullscreen(void);

/* Cycle focus: +1 forward, -1 backward */
void     tile_focus_cycle(int reverse);

/* ── Panel content callback ─────────────────────────────────────── */

typedef void (*tile_panel_render_fn)(tile_t *t, int cx, int cy, int cw, int ch);

void tile_set_panel_render(tile_panel_render_fn fn);

/* Panel content dispatcher (defined in gui_widgets.c) */
void panel_render(tile_t *t, int cx, int cy, int cw, int ch);

/* Cycle panel type for new splits (defined in gui_widgets.c) */
int gui_widgets_next_id(void);

#endif /* GUI_H */
