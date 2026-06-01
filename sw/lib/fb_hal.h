/* fb_hal.h — Pixel Framebuffer Hardware Abstraction Layer
 *
 * LOCAL_BUILD: SDL2 window rendering
 * NEORV32:     SDRAM linear framebuffer at configurable base address
 *
 * Pixel format: RGB565 (16-bit, 5-6-5)
 */

#ifndef FB_HAL_H
#define FB_HAL_H

#include <stdint.h>

/* Framebuffer dimensions and format */
#define FB_W   640
#define FB_H   480
#define FB_BPP 16   /* RGB565: 16-bit per pixel */

/* RGB565 helper: pack (r,g,b) 8-bit channels into 16-bit */
static inline uint16_t fb_rgb565(uint8_t r, uint8_t g, uint8_t b) {
    return (uint16_t)(((uint16_t)(r >> 3) << 11) |
                      ((uint16_t)(g >> 2) << 5)  |
                       (uint16_t)(b >> 3));
}

/* Named palette entries (RGB565) */
#define FB_BLACK   0x0000
#define FB_WHITE   0xFFFF
#define FB_RED     0xF800
#define FB_GREEN   0x07E0
#define FB_BLUE    0x001F
#define FB_YELLOW  0xFFE0
#define FB_CYAN    0x07FF
#define FB_MAGENTA 0xF81F
#define FB_GRAY    0x7BEF
#define FB_DKGRAY  0x39E7
#define FB_LTGRAY  0xBDF7
#define FB_ORANGE  0xFD20
#define FB_BROWN   0x9B81
#define FB_TEAL    0x0410

/* Initialize framebuffer backend */
void fb_init(void);

/* Set a single pixel */
void fb_set_pixel(int x, int y, uint16_t color);

/* Get a single pixel */
uint16_t fb_get_pixel(int x, int y);

/* Flush/present the framebuffer to display */
void fb_present(void);

/* Clear entire framebuffer to given color */
void fb_clear(uint16_t color);

/* Enable/disable pixel-controller internal test pattern when supported. */
void fb_set_debug_pattern(int enabled);

/* Shut down framebuffer backend */
void fb_shutdown(void);

#endif /* FB_HAL_H */
