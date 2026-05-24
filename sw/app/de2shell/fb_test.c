/* fb_test.c — Framebuffer HAL smoke test
 *
 * Draws an RGB332 gradient and some primitives to verify
 * the SDL2 (LOCAL_BUILD) or SDRAM (NEORV32) backend works.
 *
 * LOCAL_BUILD:  gcc -DLOCAL_BUILD -o fb_test fb_test.c fb_hal.c -lSDL2
 * NEORV32:      via makefile
 */

#include "fb_hal.h"
#include <stdio.h>

#ifdef LOCAL_BUILD
  #include <SDL.h>
#endif

static void draw_gradient(void) {
    for (int y = 0; y < FB_H; y++) {
        for (int x = 0; x < FB_W; x++) {
            uint8_t r = (uint8_t)(x * 7 / (FB_W - 1));
            uint8_t g = (uint8_t)(y * 7 / (FB_H - 1));
            uint8_t b = (uint8_t)(((x + y) * 3) / (FB_W + FB_H - 2));
            fb_set_pixel(x, y, (uint8_t)((r << 5) | (g << 2) | b));
        }
    }
}

static void draw_rect(int x0, int y0, int w, int h, uint8_t color) {
    for (int y = y0; y < y0 + h && y < FB_H; y++)
        for (int x = x0; x < x0 + w && x < FB_W; x++)
            fb_set_pixel(x, y, color);
}

/* Bresenham line */
static void draw_line(int x0, int y0, int x1, int y1, uint8_t color) {
    int dx =  x1 - x0;
    int dy = -((y1 - y0));
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

#ifdef LOCAL_BUILD
int main(int argc, char *argv[]) {
#else
int main(void) {
#endif
    fb_init();

    /* 1. Full-screen RGB gradient */
    draw_gradient();
    fb_present();

#ifdef LOCAL_BUILD
    SDL_Delay(2000);
#endif

    /* 2. Overlay: gray window with title bar */
    draw_rect(120, 80, 400, 300, FB_LTGRAY);
    draw_rect(120, 80, 400,  24, FB_DKGRAY);  /* title bar */
    draw_rect(120, 80, 400, 300, FB_BLACK);    /* border */

    /* Cross inside window */
    draw_line(140, 110, 500, 360, FB_RED);
    draw_line(140, 360, 500, 110, FB_BLUE);

    /* Small colored blocks */
    draw_rect(160, 140, 40, 40, FB_RED);
    draw_rect(210, 140, 40, 40, FB_GREEN);
    draw_rect(260, 140, 40, 40, FB_BLUE);
    draw_rect(310, 140, 40, 40, FB_YELLOW);

    fb_present();

    printf("Framebuffer test: gradient + window drawn.\n");

#ifdef LOCAL_BUILD
    SDL_Delay(4000);
#endif

    fb_shutdown();
    return 0;
}
