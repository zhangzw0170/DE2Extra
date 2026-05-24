/* screenshot.c — Render one Win30 frame and save as PPM
 * Build: gcc -DLOCAL_BUILD -O2 -I . -I ../crypto_cli -I "$(scoop prefix sdl2)/include/SDL2" -o screenshot screenshot.c gfx.c gui.c gui_widgets.c ps2_decoder.c fb_hal.c -L "$(scoop prefix sdl2)/lib" -lmingw32 -lSDL2main -lSDL2
 */
#include <stdio.h>
#include <string.h>
#include "fb_hal.h"
#include "gfx.h"
#include "gui.h"
#include "ps2_decoder.h"

static const char *icon_names[] = {
    "Snake", "Life", "Crypto", "Info",
    "Dash",  "PS/2", "Demo",   "MemTest",
    "Settings"
};

int main(void) {
    fb_init();
    ps2_dec_init();
    gui_init();

    gfx_clear(FB_TEAL);

    /* Taskbar */
    gui_create(WIDGET_TASKBAR, 0, FB_H - 24, FB_W, 24, NULL, NULL);

    /* Icon grid */
    for (int i = 0; i < 9; i++) {
        int col = i % 3, row = i / 3;
        gui_create(WIDGET_ICON, 16 + col * 80, 16 + row * 72, 32, 32, icon_names[i], NULL);
    }

    /* Calculator window */
    widget_t *calc = gui_create(WIDGET_WINDOW, 200, 40, 240, 200, "Calculator", NULL);
    gui_create(WIDGET_LABEL, 210, 68, 0, 0, "DE2Extra Calc", calc);
    gui_create(WIDGET_BUTTON, 210, 88, 96, 24, "7", calc);
    gui_create(WIDGET_BUTTON, 312, 88, 96, 24, "8", calc);
    gui_create(WIDGET_BUTTON, 210, 118, 96, 24, "4", calc);
    gui_create(WIDGET_BUTTON, 312, 118, 96, 24, "5", calc);
    gui_create(WIDGET_BUTTON, 210, 148, 96, 24, "1", calc);
    gui_create(WIDGET_BUTTON, 312, 148, 96, 24, "2", calc);

    /* About window */
    widget_t *about = gui_create(WIDGET_WINDOW, 280, 180, 280, 160, "About DE2Extra", NULL);
    gui_create(WIDGET_LABEL, 292, 208, 0, 0,
        "DE2Extra Shell v0.2\nNEORV32 RISC-V SoC\nDE2-115 Cyclone IV E", about);
    gui_create(WIDGET_BUTTON, 380, 290, 80, 24, "OK", about);

    gui_render_all();
    fb_present();

    /* Save as PPM */
    FILE *f = fopen("win30_screenshot.ppm", "wb");
    if (!f) { printf("Cannot open output\n"); return 1; }
    fprintf(f, "P6\n%d %d\n255\n", FB_W, FB_H);
    for (int y = 0; y < FB_H; y++) {
        for (int x = 0; x < FB_W; x++) {
            uint8_t c = fb_get_pixel(x, y);
            uint8_t r = (uint8_t)(((c >> 5) & 0x07) * 255 / 7);
            uint8_t g = (uint8_t)(((c >> 2) & 0x07) * 255 / 7);
            uint8_t b = (uint8_t)(( c       & 0x03) * 255 / 3);
            fputc(r, f);
            fputc(g, f);
            fputc(b, f);
        }
    }
    fclose(f);
    printf("Saved win30_screenshot.ppm\n");

    fb_shutdown();
    return 0;
}
