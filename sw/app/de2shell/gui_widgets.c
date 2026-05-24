/* gui_widgets.c — Render and key handlers for each widget type */
#include "gui.h"
#include "gfx.h"
#include "gfx_font.h"
#include <string.h>

/* ── Window ─────────────────────────────────────────────────────── */

static void render_window(widget_t *self) {
    int bx = self->x, by = self->y, bw = self->w, bh = self->h;
    const char *title = self->text;
    int active = self->active;

    /* Shadow */
    gfx_fill_rect(bx + 4, by + 4, bw, bh, FB_DKGRAY);

    /* Outer bevel */
    gfx_bevel(bx, by, bw, bh, 1);

    /* Title bar (20px) */
    uint8_t title_bg = active ? FB_BLUE : FB_GRAY;
    gfx_fill_rect(bx + 3, by + 3, bw - 6, 18, title_bg);

    /* Title text */
    if (title) {
        int tx = bx + 6;
        int max_w = bw - 6 - 24;
        int avail = max_w / FONT_W;
        int len = 0;
        while (title[len]) len++;
        int draw = len < avail ? len : avail;
        for (int i = 0; i < draw; i++)
            gfx_char(tx + i * FONT_W, by + 4, title[i], FB_WHITE, 0xFF);
    }

    /* Close button [X] */
    int cbx = bx + bw - 20;
    int cby = by + 4;
    gfx_fill_rect(cbx, cby, 16, 14, FB_LTGRAY);
    gfx_bevel(cbx, cby, 16, 14, 1);
    gfx_char(cbx + 4, cby, 'x', FB_BLACK, 0xFF);

    /* Client area */
    gfx_fill_rect(bx + 3, by + 21, bw - 6, bh - 24, FB_LTGRAY);

    /* Render children */
    widget_t *c = self->children;
    while (c) {
        if (c->visible && c->render) c->render(c);
        c = c->next;
    }
}

static int key_window(widget_t *self, const gui_event_t *ev) {
    if (!ev->is_press) return 0;

    /* ESC closes the window */
    if (ev->ascii == 0x1b) {
        self->visible = 0;
        return 1;
    }
    /* Route to children */
    widget_t *c = self->children;
    while (c) {
        if (c->focused && c->key) {
            if (c->key(c, ev)) return 1;
        }
        c = c->next;
    }
    return 0;
}

/* ── Button ─────────────────────────────────────────────────────── */

static void render_button(widget_t *self) {
    int bx = self->x, by = self->y, bw = self->w, bh = self->h;

    if (self->pressed) {
        gfx_bevel(bx, by, bw, bh, 0);
    } else {
        gfx_bevel(bx, by, bw, bh, 1);
    }
    gfx_fill_rect(bx + 3, by + 3, bw - 6, bh - 6, FB_LTGRAY);

    /* Focus highlight */
    if (self->focused) {
        gfx_rect(bx + 1, by + 1, bw - 2, bh - 2, FB_BLACK);
    }

    /* Centered text */
    if (self->text) {
        int len = 0;
        while (self->text[len]) len++;
        int tw = len * FONT_W;
        int tx = bx + (bw - tw) / 2;
        int ty = by + (bh - FONT_H) / 2;
        for (int i = 0; i < len; i++)
            gfx_char(tx + i * FONT_W, ty, self->text[i], FB_BLACK, 0xFF);
    }
}

static int key_button(widget_t *self, const gui_event_t *ev) {
    if (!ev->is_press) return 0;
    if (ev->ascii == ' ' || ev->ascii == 0x0d) {
        /* Press animation */
        self->pressed = 1;
        gui_render_all();
        /* Short delay for visual feedback */
        for (volatile int i = 0; i < 100000; i++) {}
        self->pressed = 0;
        return 1;
    }
    return 0;
}

/* ── Label ──────────────────────────────────────────────────────── */

static void render_label(widget_t *self) {
    if (!self->text) return;
    gfx_text(self->x, self->y, self->text, FB_BLACK, 0xFF);
}

/* ── TextInput ──────────────────────────────────────────────────── */

static void render_textinput(widget_t *self) {
    int bx = self->x, by = self->y, bw = self->w, bh = self->h;

    /* White background */
    gfx_fill_rect(bx, by, bw, bh, FB_WHITE);
    gfx_bevel(bx, by, bw, bh, 0);

    /* Text */
    int tx = bx + 3;
    int ty = by + (bh - FONT_H) / 2;
    int max_chars = (bw - 6) / FONT_W;
    int start = 0;
    if (self->textpos > max_chars) start = self->textpos - max_chars;

    for (int i = start; i < self->textlen && (i - start) < max_chars; i++)
        gfx_char(tx + (i - start) * FONT_W, ty, self->textbuf[i], FB_BLACK, 0xFF);

    /* Blinking cursor (drawn when focused) */
    if (self->focused) {
        int cx = tx + (self->textpos - start) * FONT_W;
        gfx_vline(cx, ty, FONT_H, FB_BLACK);
    }
}

static int key_textinput(widget_t *self, const gui_event_t *ev) {
    if (!ev->is_press) return 0;
    uint8_t ch = ev->ascii;

    if (ch == 0x08 || ch == 0x7f) {
        /* Backspace */
        if (self->textpos > 0) {
            self->textpos--;
            for (int i = self->textpos; i < self->textlen; i++)
                self->textbuf[i] = self->textbuf[i + 1];
            self->textlen--;
        }
        return 1;
    }
    if (ev->is_extended && ev->scancode == 0x6b) {
        /* Left arrow */
        if (self->textpos > 0) self->textpos--;
        return 1;
    }
    if (ev->is_extended && ev->scancode == 0x74) {
        /* Right arrow */
        if (self->textpos < self->textlen) self->textpos++;
        return 1;
    }
    if (ev->is_extended && ev->scancode == 0x6c) {
        /* Home */
        self->textpos = 0;
        return 1;
    }
    if (ev->is_extended && ev->scancode == 0x69) {
        /* End */
        self->textpos = self->textlen;
        return 1;
    }
    if (ch >= 0x20 && ch < 0x7f && self->textlen < GUI_TEXTINPUT_MAX - 1) {
        /* Insert character */
        for (int i = self->textlen; i > self->textpos; i--)
            self->textbuf[i] = self->textbuf[i - 1];
        self->textbuf[self->textpos] = (char)ch;
        self->textpos++;
        self->textlen++;
        self->textbuf[self->textlen] = '\0';
        return 1;
    }
    return 0;
}

/* ── Taskbar ────────────────────────────────────────────────────── */

static void render_taskbar(widget_t *self) {
    int bx = self->x, by = self->y, bw = self->w, bh = self->h;

    /* Background */
    gfx_fill_rect(bx, by, bw, bh, FB_DKGRAY);
    gfx_bevel(bx, by, bw, bh, 1);

    /* "DE2Extra" label */
    gfx_text(bx + 4, by + (bh - FONT_H) / 2, "DE2Extra", FB_WHITE, 0xFF);

    /* Separator */
    int sep_x = bx + 8 * FONT_W + 12;
    gfx_vline(sep_x, by + 2, bh - 4, FB_LTGRAY);
    gfx_vline(sep_x + 1, by + 2, bh - 4, FB_BLACK);
}

/* ── Icon ───────────────────────────────────────────────────────── */

static void render_icon(widget_t *self) {
    int bx = self->x, by = self->y;

    /* Focus highlight */
    if (self->focused) {
        gfx_fill_rect(bx - 2, by - 2, 36, 36, FB_BLUE);
    }

    /* 32x32 icon area — placeholder pattern */
    if (self->icon_bitmap) {
        for (int row = 0; row < 32; row++) {
            for (int col = 0; col < 32; col++) {
                int byte_idx = row * 4 + col / 8;
                int bit_idx = 7 - (col % 8);
                if (self->icon_bitmap[byte_idx] & (1 << bit_idx))
                    fb_set_pixel(bx + col, by + row, FB_WHITE);
                else
                    fb_set_pixel(bx + col, by + row, FB_BLUE);
            }
        }
    } else {
        /* Default icon: blue square with white border */
        gfx_fill_rect(bx, by, 32, 32, FB_BLUE);
        gfx_rect(bx, by, 32, 32, FB_WHITE);
    }

    /* Label below icon, centered under icon, may extend beyond icon width */
    if (self->text) {
        int len = 0;
        while (self->text[len]) len++;
        int tw = len * FONT_W;
        int tx = bx + (32 - tw) / 2;
        int ty = by + 34;
        gfx_text(tx, ty, self->text, FB_WHITE, FB_TEAL);
    }
}

static int key_icon(widget_t *self, const gui_event_t *ev) {
    if (!ev->is_press) return 0;
    if (ev->ascii == 0x0d || ev->ascii == ' ') {
        /* "Open" the icon — just visual feedback for now */
        return 1;
    }
    return 0;
}

/* ── Widget setup — assign render/key based on type ─────────────── */

void gui_widget_setup(widget_t *w) {
    if (!w) return;
    switch (w->type) {
        case WIDGET_WINDOW:
            w->render = render_window;
            w->key    = key_window;
            break;
        case WIDGET_BUTTON:
            w->render = render_button;
            w->key    = key_button;
            break;
        case WIDGET_LABEL:
            w->render = render_label;
            w->key    = NULL;
            break;
        case WIDGET_TEXTINPUT:
            w->render = render_textinput;
            w->key    = key_textinput;
            w->textbuf[0] = '\0';
            w->textpos = 0;
            w->textlen = 0;
            break;
        case WIDGET_TASKBAR:
            w->render = render_taskbar;
            w->key    = NULL;
            break;
        case WIDGET_ICON:
            w->render = render_icon;
            w->key    = key_icon;
            break;
        default:
            break;
    }
}
