/* fb_hal.h — Pixel Framebuffer Hardware Abstraction Layer
 *
 * LOCAL_BUILD: SDL2 window rendering
 * NEORV32:     SDRAM linear framebuffer at configurable base address
 *
 * This is separate from vga_hal (text mode) — both can coexist.
 * Switch between text/pixel mode at the application level.
 */

#ifndef FB_HAL_H
#define FB_HAL_H

#include <stdint.h>

/* Framebuffer dimensions and format */
#define FB_W   640
#define FB_H   480
#define FB_BPP 8    /* 256-color palette index */

/* RGB332 palette: 3-bit R, 3-bit G, 2-bit B */
static inline uint8_t fb_rgb332(uint8_t r, uint8_t g, uint8_t b) {
    return (uint8_t)(((r >> 5) << 5) | ((g >> 5) << 2) | (b >> 6));
}

/* Named palette entries (RGB332) */
#define FB_BLACK   0x00
#define FB_WHITE   0xFF
#define FB_RED     0xE0
#define FB_GREEN   0x1C
#define FB_BLUE    0x03
#define FB_YELLOW  0xFC
#define FB_CYAN    0x1F
#define FB_MAGENTA 0xE3
#define FB_GRAY    0x92
#define FB_DKGRAY  0x49
#define FB_LTGRAY  0xDB
#define FB_ORANGE  0xF8
#define FB_BROWN   0x90
#define FB_TEAL    0x12    /* Win 3.1 desktop: #008080 */

/* Initialize framebuffer backend */
void fb_init(void);

/* Set a single pixel */
void fb_set_pixel(int x, int y, uint8_t color);

/* Get a single pixel */
uint8_t fb_get_pixel(int x, int y);

/* Flush/present the framebuffer to display */
void fb_present(void);

/* Clear entire framebuffer to given color */
void fb_clear(uint8_t color);

/* Shut down framebuffer backend */
void fb_shutdown(void);

#endif /* FB_HAL_H */
