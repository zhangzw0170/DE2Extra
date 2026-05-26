/* gui.c — Tiling window manager implementation
 *
 * Binary tree of tile nodes. Layout is computed top-down.
 * Rendering walks the tree and draws each leaf's frame + content.
 */
#include "gui.h"
#include "gfx.h"
#include <stdio.h>
#include <string.h>

/* ── Static pool ────────────────────────────────────────────────── */

static tile_t pool[TILE_MAX]
#ifdef DE2SHELL_RTOS
    __attribute__((section(".sdram_bss")))
#endif
;

static tile_t *root;
static tile_t *focused;
static tile_panel_render_fn panel_render_fn;

/* ── Helpers ───────────────────────────────────────────────────── */

static tile_t *alloc_node(void) {
    for (int i = 0; i < TILE_MAX; i++) {
        if (pool[i].type < 0) return &pool[i];
    }
    return NULL;
}

static int leaf_count(tile_t *t) {
    if (!t) return 0;
    if (t->type == TILE_LEAF) return 1;
    return leaf_count(t->child[0]) + leaf_count(t->child[1]);
}

static int collect_leaves(tile_t *t, tile_t **out, int max) {
    if (!t) return 0;
    if (t->type == TILE_LEAF) {
        if (out && max > 0) { *out = t; return 1; }
        return 0;
    }
    int n = 0;
    n += collect_leaves(t->child[0], out ? out + n : NULL, out ? max - n : 0);
    n += collect_leaves(t->child[1], out ? out + n : NULL, out ? max - n : 0);
    return n;
}

/* ── Init ───────────────────────────────────────────────────────── */

void tile_init(void) {
    memset(pool, 0, sizeof(pool));
    for (int i = 0; i < TILE_MAX; i++) pool[i].type = -1;
    root = alloc_node();
    root->type = TILE_LEAF;
    root->focused = 1;
    root->active = 1;
    root->ratio = 0.5f;
    root->id = 1;
    snprintf(root->title, TILE_TITLE_MAX, "shell");
    focused = root;
}

/* ── Split ──────────────────────────────────────────────────────── */

tile_t *tile_split(int dir) {
    if (!focused || leaf_count(root) >= TILE_MAX - 1) return NULL;

    tile_t *parent = focused->parent;

    tile_t *split = alloc_node();
    if (!split) return NULL;

    tile_t *sibling = alloc_node();
    if (!sibling) { split->type = -1; return NULL; }

    split->type = (dir == 0) ? TILE_SPLIT_H : TILE_SPLIT_V;
    split->ratio = 0.5f;
    split->child[0] = focused;
    split->child[1] = sibling;
    split->parent = parent;

    sibling->type = TILE_LEAF;
    sibling->parent = split;
    sibling->ratio = 0.5f;
    sibling->id = gui_widgets_next_id();
    switch (sibling->id) {
        case 2: snprintf(sibling->title, TILE_TITLE_MAX, "monitor"); break;
        case 3: snprintf(sibling->title, TILE_TITLE_MAX, "info"); break;
        default: snprintf(sibling->title, TILE_TITLE_MAX, "shell"); break;
    }

    focused->parent = split;
    focused->focused = 0;
    focused->active = 0;

    if (parent) {
        if (parent->child[0] == focused) parent->child[0] = split;
        else parent->child[1] = split;
    } else {
        root = split;
    }

    focused = sibling;
    sibling->focused = 1;
    sibling->active = 1;

    return sibling;
}

/* ── Close ──────────────────────────────────────────────────────── */

void tile_close(void) {
    if (!focused || leaf_count(root) <= 1) return;

    tile_t *victim = focused;
    tile_t *parent = victim->parent;
    tile_t *sibling = (parent->child[0] == victim)
                      ? parent->child[1] : parent->child[0];
    tile_t *gp = parent->parent;

    sibling->parent = gp;

    if (gp) {
        if (gp->child[0] == parent) gp->child[0] = sibling;
        else gp->child[1] = sibling;
    } else {
        root = sibling;
    }

    victim->type = -1;
    parent->type = -1;

    focused = sibling;
    sibling->focused = 1;
    sibling->active = 1;
}

/* ── Focus navigation ───────────────────────────────────────────── */

static int node_contains(tile_t *ancestor, tile_t *desc) {
    if (!ancestor || !desc) return 0;
    if (ancestor == desc) return 1;
    if (ancestor->type == TILE_LEAF) return 0;
    return node_contains(ancestor->child[0], desc) ||
           node_contains(ancestor->child[1], desc);
}

static tile_t *find_neighbor(tile_t *from, int dir) {
    /* dir: 0=left  1=right  2=up  3=down */
    tile_t *leaves[TILE_MAX];
    int count = collect_leaves(root, leaves, TILE_MAX);
    if (count <= 1) return NULL;

    tile_t *best = NULL;
    int best_dist = 999999;

    for (int i = 0; i < count; i++) {
        tile_t *l = leaves[i];
        if (l == from) continue;

        int dx = 0, dy = 0;
        switch (dir) {
            case 0: dx = from->x - (l->x + l->w); break;
            case 1: dx = (l->x) - (from->x + from->w); break;
            case 2: dy = from->y - (l->y + l->h); break;
            case 3: dy = (l->y) - (from->y + from->h); break;
        }

        if (dx < 0 || dy < 0) continue;

        /* Perpendicular overlap */
        int overlap = 0;
        if (dir <= 1) {
            int t = (from->y > l->y) ? from->y : l->y;
            int b = ((from->y + from->h) < (l->y + l->h))
                    ? (from->y + from->h) : (l->y + l->h);
            overlap = b - t;
        } else {
            int le = (from->x > l->x) ? from->x : l->x;
            int ri = ((from->x + from->w) < (l->x + l->w))
                     ? (from->x + from->w) : (l->x + l->w);
            overlap = ri - le;
        }
        if (overlap <= 0) continue;

        int dist = (dir <= 1) ? dx : dy;
        if (dist < best_dist) { best_dist = dist; best = l; }
    }
    return best;
}

void tile_focus_dir(int dir) {
    if (!focused) return;
    tile_t *next = find_neighbor(focused, dir);
    if (!next) return;
    focused->focused = 0;
    focused->active = 0;
    focused = next;
    focused->focused = 1;
    focused->active = 1;
}

tile_t *tile_focused(void) { return focused; }
tile_t *tile_root(void)    { return root; }

void tile_set_panel_render(tile_panel_render_fn fn) { panel_render_fn = fn; }

/* ── Resize ──────────────────────────────────────────────────────── */

void tile_resize(int axis, int sign) {
    /* axis: 0=H(left/right) 1=V(up/down)
     * sign: +1=expand focused direction, -1=shrink */
    if (!focused) return;

    int target_type = (axis == 0) ? TILE_SPLIT_H : TILE_SPLIT_V;
    tile_t *node = focused->parent;

    while (node) {
        if (node->type == target_type) {
            int is_first = node_contains(node->child[0], focused);
            float step = 0.05f * sign;
            if (is_first) node->ratio += step;
            else           node->ratio -= step;
            if (node->ratio < 0.1f) node->ratio = 0.1f;
            if (node->ratio > 0.9f) node->ratio = 0.9f;
            return;
        }
        node = node->parent;
    }
}

/* ── Fullscreen toggle ───────────────────────────────────────────── */

static int zoomed;
static tile_t *zoom_tile;

void tile_toggle_fullscreen(void) {
    if (zoomed) {
        zoomed = 0;
        zoom_tile = NULL;
    } else if (focused) {
        zoom_tile = focused;
        zoomed = 1;
    }
}

/* ── Focus cycle ─────────────────────────────────────────────────── */

void tile_focus_cycle(int reverse) {
    tile_t *leaves[TILE_MAX];
    int count = collect_leaves(root, leaves, TILE_MAX);
    if (count <= 1) return;

    int idx = -1;
    for (int i = 0; i < count; i++) {
        if (leaves[i] == focused) { idx = i; break; }
    }

    focused->focused = 0;
    focused->active = 0;

    if (reverse) idx = (idx > 0) ? idx - 1 : count - 1;
    else           idx = (idx + 1) % count;

    focused = leaves[idx];
    focused->focused = 1;
    focused->active = 1;
}

/* ── Layout ─────────────────────────────────────────────────────── */

static void layout_recurse(tile_t *t, int x, int y, int w, int h) {
    if (!t) return;
    t->x = x; t->y = y; t->w = w; t->h = h;

    if (t->type == TILE_SPLIT_H) {
        int w0 = (int)(w * t->ratio);
        if (w0 < 60) w0 = 60;
        if (w - w0 < 60) w0 = w - 60;
        layout_recurse(t->child[0], x,     y, w0,     h);
        layout_recurse(t->child[1], x + w0, y, w - w0, h);
    } else if (t->type == TILE_SPLIT_V) {
        int h0 = (int)(h * t->ratio);
        if (h0 < 40) h0 = 40;
        if (h - h0 < 40) h0 = h - 40;
        layout_recurse(t->child[0], x, y,     w, h0);
        layout_recurse(t->child[1], x, y + h0, w, h - h0);
    }
}

void tile_layout(void) {
    if (zoomed && zoom_tile) {
        zoom_tile->x = 0;
        zoom_tile->y = 0;
        zoom_tile->w = FB_W;
        zoom_tile->h = FB_H - 24;
    } else {
        layout_recurse(root, 0, 0, FB_W, FB_H - 24);
    }
}

/* ── Render ─────────────────────────────────────────────────────── */

#define TITLE_H 18

static void render_tile(tile_t *t) {
    if (!t) return;

    if (t->type == TILE_LEAF) {
        /* Frame */
        uint8_t frame_c = t->focused ? FB_WHITE : FB_DKGRAY;
        gfx_rect(t->x, t->y, t->w, t->h, frame_c);

        /* Title bar */
        uint8_t bg = t->active ? FB_BLUE : FB_GRAY;
        gfx_fill_rect(t->x + 1, t->y + 1, t->w - 2, TITLE_H, bg);

        if (t->title[0])
            gfx_text(t->x + 4, t->y + 2, t->title, FB_WHITE, 0xFF);

        /* Content area */
        int cx = t->x + 1, cy = t->y + 1 + TITLE_H;
        int cw = t->w - 2, ch = t->h - 2 - TITLE_H;
        if (cw > 0 && ch > 0) {
            gfx_fill_rect(cx, cy, cw, ch, FB_BLACK);
            if (panel_render_fn) panel_render_fn(t, cx, cy, cw, ch);
        }
    } else {
        /* Separator */
        if (t->type == TILE_SPLIT_H) {
            int sx = t->child[0]->x + t->child[0]->w;
            gfx_vline(sx, t->y, t->h, FB_DKGRAY);
            gfx_vline(sx + 1, t->y, t->h, FB_BLACK);
        } else {
            int sy = t->child[0]->y + t->child[0]->h;
            gfx_hline(t->x, sy, t->w, FB_DKGRAY);
            gfx_hline(t->x, sy + 1, t->w, FB_BLACK);
        }
        render_tile(t->child[0]);
        render_tile(t->child[1]);
    }
}

void tile_render_all(void) {
    gfx_clear(FB_BLACK);

    if (zoomed && zoom_tile) {
        render_tile(zoom_tile);
    } else {
        render_tile(root);
    }

    /* Status bar */
    int sby = FB_H - 24;
    gfx_fill_rect(0, sby, FB_W, 24, FB_DKGRAY);
    gfx_bevel(0, sby, FB_W, 24, 1);
    gfx_text(4, sby + 6, "DE2Extra", FB_WHITE, 0xFF);

    if (focused && focused->title[0]) {
        char buf[32];
        snprintf(buf, sizeof(buf), "[%s]", focused->title);
        gfx_text(FB_W - 160, sby + 6, buf, FB_LTGRAY, 0xFF);
    }

    if (zoomed)
        gfx_text(FB_W - 260, sby + 6, "[ZOOM]", FB_YELLOW, 0xFF);

    fb_present();
}
