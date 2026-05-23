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

/* RGB332 color constants */
#define VGA_BLACK   0x00
#define VGA_RED     0xE0
#define VGA_GREEN   0x1C
#define VGA_BLUE    0x03
#define VGA_YELLOW  0xFC
#define VGA_CYAN    0x1F
#define VGA_MAGENTA 0xE3
#define VGA_WHITE   0xFF
#define VGA_GRAY    0x92

/* Terminal dimensions */
#define VGA_COLS 80
#define VGA_ROWS 25

/* Initialize VGA (clear screen, hide cursor, home) */
void vga_init(void);

/* Write a character at current cursor position, advance cursor */
void vga_putc(char c, uint8_t color);

/* Write a null-terminated string */
void vga_puts(const char *s, uint8_t color);

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
