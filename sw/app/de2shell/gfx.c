/* gfx.c -- Pixel drawing primitives implementation */
#include "gfx.h"
#include "gfx_font.h"
#include <string.h>

#ifdef LOCAL_BUILD
#include <SDL.h>
#endif

/* ── Basic primitives ──────────────────────────────────────────── */

void gfx_clear(uint8_t color) {
    fb_clear(color);
}

void gfx_fill_rect(int x, int y, int w, int h, uint8_t color) {
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > FB_W) w = FB_W - x;
    if (y + h > FB_H) h = FB_H - y;
    if (w <= 0 || h <= 0) return;
    for (int row = y; row < y + h; row++)
        for (int col = x; col < x + w; col++)
            fb_set_pixel(col, row, color);
}

void gfx_rect(int x, int y, int w, int h, uint8_t color) {
    gfx_hline(x, y, w, color);
    gfx_hline(x, y + h - 1, w, color);
    gfx_vline(x, y, h, color);
    gfx_vline(x + w - 1, y, h, color);
}

void gfx_hline(int x, int y, int w, uint8_t color) {
    if (y < 0 || y >= FB_H) return;
    int x0 = x < 0 ? 0 : x;
    int x1 = x + w;
    if (x1 > FB_W) x1 = FB_W;
    for (int i = x0; i < x1; i++)
        fb_set_pixel(i, y, color);
}

void gfx_vline(int x, int y, int h, uint8_t color) {
    if (x < 0 || x >= FB_W) return;
    int y0 = y < 0 ? 0 : y;
    int y1 = y + h;
    if (y1 > FB_H) y1 = FB_H;
    for (int i = y0; i < y1; i++)
        fb_set_pixel(x, i, color);
}

void gfx_line(int x0, int y0, int x1, int y1, uint8_t color) {
    int dx = x1 - x0;
    int dy = -(y1 - y0);
    int sx = dx >= 0 ? 1 : -1;
    int sy = dy >= 0 ? 1 : -1;
    dx *= sx;
    dy *= sy;
    int err = dx - dy;

    for (;;) {
        fb_set_pixel(x0, y0, color);
        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;
        if (e2 > -dy) { err -= dy; x0 += sx; }
        if (e2 <  dx) { err += dx; y0 += sy; }
    }
}

/* ── Text rendering ─────────────────────────────────────────────── */

void gfx_char(int x, int y, char c, uint8_t fg, uint8_t bg) {
    uint8_t ch = (uint8_t)c;
    if (ch >= FONT_CHARS) ch = 0;
    for (int row = 0; row < FONT_H; row++) {
        uint8_t bits = font_8x16[ch][row];
        for (int col = 0; col < FONT_W; col++) {
            int px = x + col;
            int py = y + row;
            if (px < 0 || px >= FB_W || py < 0 || py >= FB_H) continue;
            if (bits & (0x80 >> col))
                fb_set_pixel(px, py, fg);
            else if (bg != 0xFF)
                fb_set_pixel(px, py, bg);
        }
    }
}

int gfx_text(int x, int y, const char *s, uint8_t fg, uint8_t bg) {
    int cx = x, cy = y;
    while (*s) {
        if (*s == '\n') {
            cx = x;
            cy += FONT_H;
        } else {
            gfx_char(cx, cy, *s, fg, bg);
            cx += FONT_W;
        }
        s++;
    }
    return cx - x;
}

/* ── Crypto visualization helpers ────────────────────────────────── */

static int isqrt(int n) {
    if (n <= 0) return 0;
    int x = n, y = (x + 1) / 2;
    while (y < x) { x = y; y = (x + n / x) / 2; }
    return x;
}

void gfx_rounded_rect(int x, int y, int w, int h, int r, uint8_t color) {
    if (r <= 0) { gfx_fill_rect(x, y, w, h, color); return; }
    if (r > w / 2) r = w / 2;
    if (r > h / 2) r = h / 2;
    gfx_fill_rect(x + r, y, w - 2*r, h, color);
    gfx_fill_rect(x, y + r, w, h - 2*r, color);
    int r2 = r * r;
    for (int dy = 0; dy < r; dy++) {
        for (int dx = 0; dx < r; dx++) {
            if ((r - 1 - dx) * (r - 1 - dx) + (r - 1 - dy) * (r - 1 - dy) < r2) {
                fb_set_pixel(x + dx, y + dy, color);
                fb_set_pixel(x + w - 1 - dx, y + dy, color);
                fb_set_pixel(x + dx, y + h - 1 - dy, color);
                fb_set_pixel(x + w - 1 - dx, y + h - 1 - dy, color);
            }
        }
    }
}

void gfx_arrow(int x0, int y0, int x1, int y1, uint8_t color) {
    gfx_line(x0, y0, x1, y1, color);
    int dx = x1 - x0, dy = y1 - y0;
    int len = isqrt(dx * dx + dy * dy);
    if (len < 4) return;
    int sz = len < 16 ? len / 2 : 8;
    int bx = sz * dx / len;
    int by = sz * dy / len;
    gfx_line(x1, y1, x1 - bx - by/2, y1 - by + bx/2, color);
    gfx_line(x1, y1, x1 - bx + by/2, y1 - by - bx/2, color);
}

void gfx_hex_cell(int x, int y, uint8_t value, uint8_t fg, uint8_t bg) {
    gfx_fill_rect(x, y, 16, 16, bg);
    gfx_rect(x, y, 16, 16, fg);
    static const char hx[] = "0123456789ABCDEF";
    gfx_char(x, y, hx[value >> 4], fg, 0xFF);
    gfx_char(x + 8, y, hx[value & 0xF], fg, 0xFF);
}

void gfx_progress_bar(int x, int y, int w, int h, int cur, int total, uint8_t fg, uint8_t bg) {
    gfx_fill_rect(x, y, w, h, bg);
    int fill = (total > 0) ? (cur * w / total) : 0;
    if (fill > w) fill = w;
    if (fill > 0) gfx_fill_rect(x, y, fill, h, fg);
}

/* ── Win 3.0 specific ───────────────────────────────────────────── */

void gfx_bevel(int x, int y, int w, int h, int raised) {
    uint8_t hi = raised ? FB_WHITE : FB_DKGRAY;
    uint8_t lo = raised ? FB_DKGRAY : FB_WHITE;
    /* outer highlight (top, left) */
    gfx_hline(x, y, w, hi);
    gfx_vline(x, y, h, hi);
    /* outer shadow (bottom, right) */
    gfx_hline(x, y + h - 1, w, lo);
    gfx_vline(x + w - 1, y, h, lo);
    /* inner highlight */
    gfx_hline(x + 1, y + 1, w - 2, hi);
    gfx_vline(x + 1, y + 1, h - 2, hi);
    /* inner shadow */
    gfx_hline(x + 1, y + h - 2, w - 2, lo);
    gfx_vline(x + w - 2, y + 1, h - 2, lo);
}

void gfx_window_frame(int x, int y, int w, int h, const char *title, int active) {
    uint8_t title_bg = active ? FB_BLUE : FB_GRAY;
    int title_h = 18;

    /* outer beveled border */
    gfx_bevel(x, y, w, h, 1);

    /* title bar */
    gfx_fill_rect(x + 3, y + 3, w - 6, title_h, title_bg);

    /* title text */
    if (title) {
        int len = 0;
        while (title[len]) len++;
        int tx = x + 6;
        int max_w = w - 6 - 24;  /* leave room for close button */
        int avail = (max_w / FONT_W);
        int draw = len < avail ? len : avail;
        for (int i = 0; i < draw; i++)
            gfx_char(tx + i * FONT_W, y + 4, title[i], FB_WHITE, 0xFF);
    }

    /* close button [X] */
    int bx = x + w - 20;
    int by = y + 4;
    gfx_fill_rect(bx, by, 16, 14, FB_LTGRAY);
    gfx_bevel(bx, by, 16, 14, 1);
    gfx_char(bx + 4, by + 0, 'x', FB_BLACK, 0xFF);

    /* client area */
    gfx_fill_rect(x + 3, y + 3 + title_h, w - 6, h - 6 - title_h, FB_LTGRAY);
}
