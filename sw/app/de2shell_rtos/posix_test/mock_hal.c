/* mock_hal.c — POSIX mock for NEORV32 hardware + de2shell HAL
 *
 * Replaces VGA/PS/2/GPIO/LCD/UART with stdout/stdin.
 * Provides stub program_t structs for all de2shell programs.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"

/* ── Mock VGA colors ──────────────────────────────────────────── */

#define VGA_WHITE  0xFFFF
#define VGA_GREEN  0x07E0
#define VGA_CYAN   0x07FF
#define VGA_GRAY   0x8410
#define VGA_RED    0xF800
#define VGA_BLACK  0x0000
#define VGA_ROWS   25
#define VGA_COLS   80

static int cursor_col = 0;
static int cursor_row = 0;

/* ── NEORV32 UART stubs ───────────────────────────────────────── */

void neorv32_uart0_setup(uint32_t baud, uint32_t irq) { (void)baud; (void)irq; }
void neorv32_uart0_puts(const char *s) { fputs(s, stdout); fflush(stdout); }
int neorv32_uart0_char_received(void) { return 0; }
char neorv32_uart0_getc(void) { return 0; }

/* ── NEORV32 RTE / CSR stubs ──────────────────────────────────── */

void neorv32_rte_setup(void) {}
void neorv32_cpu_csr_write(uint32_t csr, uint32_t val) { (void)csr; (void)val; }
uint32_t neorv32_cpu_csr_read(uint32_t csr) {
    (void)csr;
    return 0;
}

/* ── NEORV32 GPIO stubs ───────────────────────────────────────── */

void neorv32_gpio_port_set(uint32_t mask) { (void)mask; }

/* ── VGA HAL ──────────────────────────────────────────────────── */

void vga_init(void) {}

void vga_clear(void) {
    printf("\033[2J\033[H");
    cursor_col = cursor_row = 0;
}

void vga_putc(char c, uint16_t color) {
    (void)color;
    if (c == '\n') {
        putchar('\n');
        cursor_col = 0;
        cursor_row++;
    } else if (c == '\b') {
        putchar('\b');
        putchar(' ');
        putchar('\b');
        if (cursor_col > 0) cursor_col--;
    } else {
        putchar(c);
        cursor_col++;
    }
    fflush(stdout);
}

void vga_puts(const char *s, uint16_t color) {
    (void)color;
    while (*s) vga_putc(*s++, color);
}

void vga_goto(int col, int row) {
    printf("\033[%d;%dH", row + 1, col + 1);
    cursor_col = col;
    cursor_row = row;
    fflush(stdout);
}

int vga_col(void) { return cursor_col; }
int vga_row(void) { return cursor_row; }

/* ── GPIO HAL ─────────────────────────────────────────────────── */

void gpio_write_out(uint32_t val) { (void)val; }

/* ── Board status ─────────────────────────────────────────────── */

void board_status_init(void) {}
void board_status_set_program(uint8_t id, uint8_t state, uint8_t flags, uint8_t data) {
    (void)id; (void)state; (void)flags; (void)data;
}

/* ── FB HAL (pixel mode) ──────────────────────────────────────── */

void fb_shutdown(void) {}

/* ── LCD HAL ──────────────────────────────────────────────────── */

void lcd_init(void) {}
void lcd_clear(void) {}
void lcd_write_line(const char *s, int line) { (void)s; (void)line; }
void lcd_write_lines(const char *l1, const char *l2) { (void)l1; (void)l2; }

/* ── PS/2 decoder stub ────────────────────────────────────────── */

typedef struct {
    uint8_t ascii;
    uint8_t scancode;
    uint8_t is_press;
    uint8_t is_extended;
    uint8_t has_ascii;
    char name[16];
} ps2_key_t;

void ps2_dec_init(void) {}
int ps2_dec_feed(uint8_t raw, ps2_key_t *key) { (void)raw; (void)key; return 0; }
uint8_t ps2_dec_shift(void) { return 0; }

/* ── Program stubs ────────────────────────────────────────────── */

typedef struct {
    const char *name;
    const char *help;
    void (*init)(void);
    void (*update)(void);
    void (*input)(char c);
    void (*ir_input)(uint8_t cmd);
    int  (*finish)(void);
} program_t;

static void stub_init(void) {}
static void stub_update(void) {}
static void stub_input(char c) { (void)c; }
static void stub_ir_input(uint8_t cmd) { (void)cmd; }
static int stub_finish(void) { return 0; }

#define STUB_PROG(n, h) \
    const program_t prog_##n = { .name = #n, .help = h, \
        .init = stub_init, .update = stub_update, .input = stub_input, \
        .ir_input = stub_ir_input, .finish = stub_finish }

STUB_PROG(hello,   "LED chaser");
STUB_PROG(memtest, "SDRAM diagnostics");
STUB_PROG(crypto,  "AES/SHA/SM4 CLI");
STUB_PROG(ps2,     "PS/2 keyboard test");
STUB_PROG(snake,   "Snake game");
STUB_PROG(life,    "Conway's Game of Life");
STUB_PROG(info,    "System dashboard");
STUB_PROG(monitor, "RISC-V instruction monitor");
STUB_PROG(demo,    "11 course labs");
STUB_PROG(win30,   "Win 3.0 GUI");

uint8_t last_ir_cmd = 0;

/* ── CLI output buffer (application-provided) ─────────────────── */

char cOutputBuffer[512];
