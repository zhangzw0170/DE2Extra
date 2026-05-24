/* gfx.h -- Pixel drawing primitives for framebuffer GUI
 *
 * Built on fb_hal.h (640x480, 8-bit RGB332).
 * Win 3.0 specific: 3D beveled borders, bitmap text.
 */
#ifndef GFX_H
#define GFX_H

#include <stdint.h>
#include "fb_hal.h"

/* ── Basic primitives ──────────────────────────────────────────── */

void gfx_clear(uint8_t color);
void gfx_fill_rect(int x, int y, int w, int h, uint8_t color);
void gfx_rect(int x, int y, int w, int h, uint8_t color);
void gfx_hline(int x, int y, int w, uint8_t color);
void gfx_vline(int x, int y, int h, uint8_t color);
void gfx_line(int x0, int y0, int x1, int y1, uint8_t color);

/* ── Text rendering ─────────────────────────────────────────────── */

/* Render one character at pixel position (x, y). bg=0xFF means transparent. */
void gfx_char(int x, int y, char c, uint8_t fg, uint8_t bg);

/* Render a string. Handles '\n'. Returns pixel width consumed. */
int gfx_text(int x, int y, const char *s, uint8_t fg, uint8_t bg);

/* ── Win 3.0 specific ───────────────────────────────────────────── */

/* 3D beveled rectangle: raised=1 → highlighted top-left, shadow bottom-right.
   Uses FB_WHITE for highlight, FB_DKGRAY for shadow. Outer 2px bevel. */
void gfx_bevel(int x, int y, int w, int h, int raised);

/* Window frame: title bar + beveled border + close button. */
void gfx_window_frame(int x, int y, int w, int h, const char *title, int active);

#endif /* GFX_H */
