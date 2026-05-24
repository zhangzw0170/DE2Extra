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

/* Terminal dimensions */
#define VGA_COLS 80
#define VGA_ROWS 25

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

/* Show/hide cursor */
void vga_cursor_show(int show);

/* Get current cursor column */
int vga_col(void);

/* Get current cursor row */
int vga_row(void);

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
