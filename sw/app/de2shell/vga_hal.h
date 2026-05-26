/* vga_hal.h — VGA Hardware Abstraction Layer
 *
 * LOCAL_BUILD: maps to ANSI terminal escape codes
 * NEORV32:     maps to VGA text buffer via Wishbone/XBUS
 */

#ifndef VGA_HAL_H
#define VGA_HAL_H

#include <stdint.h>

#ifndef NULL
  #define NULL ((void*)0)
#endif

/* RGB565 color constants */
#define VGA_BLACK   0x0000
#define VGA_RED     0xF800
#define VGA_GREEN   0x07E0
#define VGA_BLUE    0x001F
#define VGA_YELLOW  0xFFE0
#define VGA_CYAN    0x07FF
#define VGA_MAGENTA 0xF81F
#define VGA_WHITE   0xFFFF
#define VGA_GRAY    0x7BEF
#define VGA_DKGRAY  0x4208

/* Terminal dimensions */
#define VGA_COLS 80
#define VGA_ROWS 30

/* Initialize VGA (clear screen, show static cursor, home) */
void vga_init(void);

/* Write a character at current cursor position, advance cursor */
void vga_putc(char c, uint16_t color);

/* Write a null-terminated string */
void vga_puts(const char *s, uint16_t color);

/* Move cursor to (col, row) — 0-based */
void vga_goto(int col, int row);

/* Clear entire screen */
void vga_clear(void);

/* Clear one text row using the given foreground color */
void vga_clear_line(int row, uint16_t color);

/* Monotonic counter incremented by every vga_clear() */
uint32_t vga_clear_epoch(void);

/* Show/hide cursor */
void vga_cursor_show(int show);

/* Get current cursor column */
int vga_col(void);

/* Get current cursor row */
int vga_row(void);

/* Read one text cell character back from the visible VGA text buffer. */
char vga_read_char(int col, int row);

/* Restrict automatic scrolling/wrapping to a text window [top, bottom]. */
void vga_set_scroll_region(int top, int bottom);

/* Restore the text window to the full screen. */
void vga_reset_scroll_region(void);

/* Wait for VGA vertical blank (polls REG_STATUS bit 0).
 * All subsequent writes land in one blanking interval. */
void vga_wait_vblank(void);

/* Print 32-bit hex value */
void vga_puthex32(uint32_t val);

/* ── Program Interface (shared with shell) ─────────────────────── */

typedef struct {
    const char *name;
    const char *help;
    void (*init)(void);
    void (*update)(void);
    void (*input)(char c);
    void (*ir_input)(uint8_t cmd);
    int  (*finish)(void);
} program_t;

#endif /* VGA_HAL_H */
