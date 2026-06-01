/* conway_hw.c — Hardware-accelerated Conway's Game of Life
 *
 * Uses FPGA conway_engine at 0xF0011000 for grid computation.
 * CPU reads grid rows via MMIO and writes to VGA text terminal.
 *
 * Registers:
 *   0x00 [W] cmd: bit0=clear, bit1=randomize, bit2=step, bit3=auto_run
 *   0x04 [W] control: bits[15:8]=row_index
 *   0x08 [R] status: bit0=busy, bit1=auto_run, bits[17:2]=generation
 *   0x0C [R] population [15:0]
 *   0x10 [R] grid_row: 80-bit row data
 */
#include "board_status.h"
#include "vga_hal.h"
#include "ps2_decoder.h"
#include <stdint.h>

#define CONWAY_BASE  ((volatile uint32_t *)0xF0011000u)

#define CONWAY_CMD      (*(CONWAY_BASE + 0))  /* W */
#define CONWAY_CTRL     (*(CONWAY_BASE + 1))  /* W */
#define CONWAY_STATUS   (*(CONWAY_BASE + 2))  /* R */
#define CONWAY_POP      (*(CONWAY_BASE + 3))  /* R */
#define CONWAY_GRID_LO  (*(CONWAY_BASE + 4))  /* R, bits[31:0] */
#define CONWAY_GRID_HI  (*(CONWAY_BASE + 5))  /* R, bits[79:32] */

static int initialized;
static int edit_mode;
static int cursor_x, cursor_y;
static int frame_count;
static int speed_ms = 200;

/* ── Hardware helpers ────────────────────────────────────────────── */

static void hw_set_row(int row) {
    CONWAY_CTRL = (uint32_t)((row & 0x1F) << 8);
}

static void hw_read_row(int row, uint32_t *lo, uint32_t *hi) {
    hw_set_row(row);
    /* Read both words after setting row index */
    *lo = CONWAY_GRID_LO;
    *hi = CONWAY_GRID_HI;
}

#define HW_TIMEOUT 1000000  /* ~20ms @50MHz */

static int hw_busy(void) {
    return (int)(CONWAY_STATUS & 1u);
}

static int hw_wait(int timeout) {
    while (timeout-- > 0 && hw_busy()) {}
    return timeout <= 0;  /* 1 = timed out */
}

static int hw_auto_run(void) {
    return (int)((CONWAY_STATUS >> 1) & 1u);
}

static uint16_t hw_generation(void) {
    return (uint16_t)(CONWAY_STATUS >> 2);
}

static uint16_t hw_population(void) {
    return (uint16_t)(CONWAY_POP);
}

static int hw_clear(void) {
    CONWAY_CMD = 1u;
    return hw_wait(HW_TIMEOUT);
}

static int hw_randomize(uint16_t seed) {
    CONWAY_CMD = (2u | ((uint32_t)seed << 16));
    return hw_wait(HW_TIMEOUT);
}

static int hw_step(void) {
    CONWAY_CMD = 4u;
    return hw_wait(HW_TIMEOUT);
}

static void hw_auto_toggle(void) {
    CONWAY_CMD = 8u;
}

/* ── Display ──────────────────────────────────────────────────────── */

static void draw_cell(int x, int y, uint32_t lo, uint32_t hi) {
    int bit;
    if (x < 32) bit = (lo >> x) & 1;
    else if (x < 64) bit = (lo >> x) & 1;
    else bit = (hi >> (x - 64)) & 1;

    char ch = bit ? '#' : '.';
    uint16_t color = bit ? VGA_WHITE : VGA_DKGRAY;
    if (edit_mode && x == cursor_x && y == cursor_y) {
        ch = bit ? 'O' : '+';
        color = VGA_YELLOW;
    }
    vga_goto(x + 1, y + 3);
    vga_putc(ch, color);
}

#define CONWAY_DISP_COLS 78  /* 80 hardware cols - 2 for border */

static void draw_grid(void) {
    for (int y = 0; y < 25; y++) {
        uint32_t lo, hi;
        hw_read_row(y, &lo, &hi);

        vga_goto(1, y + 3);
        for (int x = 0; x < 32 && x < CONWAY_DISP_COLS; x++) {
            char ch = (lo >> x) & 1 ? '#' : '.';
            uint16_t color = (lo >> x) & 1 ? VGA_WHITE : VGA_DKGRAY;
            if (edit_mode && x == cursor_x && y == cursor_y) {
                ch = (lo >> x) & 1 ? 'O' : '+';
                color = VGA_YELLOW;
            }
            vga_putc(ch, color);
        }
        for (int x = 32; x < 64 && x < CONWAY_DISP_COLS; x++) {
            char ch = (lo >> x) & 1 ? '#' : '.';
            uint16_t color = (lo >> x) & 1 ? VGA_WHITE : VGA_DKGRAY;
            if (edit_mode && x == cursor_x && y == cursor_y) {
                ch = (lo >> x) & 1 ? 'O' : '+';
                color = VGA_YELLOW;
            }
            vga_putc(ch, color);
        }
        for (int x = 64; x < CONWAY_DISP_COLS; x++) {
            int shift = x - 64;
            char ch = (hi >> shift) & 1 ? '#' : '.';
            uint16_t color = (hi >> shift) & 1 ? VGA_WHITE : VGA_DKGRAY;
            if (edit_mode && x == cursor_x && y == cursor_y) {
                ch = (hi >> shift) & 1 ? 'O' : '+';
                color = VGA_YELLOW;
            }
            vga_putc(ch, color);
        }
    }
}

static void draw_hud(void) {
    uint16_t gen = hw_generation();
    uint16_t pop = hw_population();
    uint8_t state = edit_mode ? BOARD_STATE_EDIT : BOARD_STATE_RUN;

    board_status_set_program(10u, state, 0u,
                             (uint16_t)(((cursor_y & 0xffu) << 8) | (cursor_x & 0xffu)));

    vga_goto(0, 0);
    vga_puts("ConwayHW Gen:", VGA_CYAN);
    vga_puthex32(gen);
    vga_puts(" Pop:", VGA_WHITE);
    vga_puthex32(pop);
    vga_puts(" ", VGA_WHITE);
    vga_puts(edit_mode ? "STOP" : "RUN ", VGA_YELLOW);
    vga_puts("SPD:", VGA_WHITE);
    vga_puthex32((uint32_t)speed_ms);

    vga_goto(0, 1);
    vga_puts("Arrows move  ENTER run/stop  R random  C clear  Q quit (read-only)", VGA_GRAY);
}

static void move_cursor(int dx, int dy) {
    int old_x = cursor_x, old_y = cursor_y;
    cursor_x = (cursor_x + dx + 80) % 80;
    cursor_y = (cursor_y + dy + 25) % 25;
    /* Redraw only old and new cell */
    uint32_t lo, hi;
    hw_read_row(old_y, &lo, &hi);
    draw_cell(old_x, old_y, lo, hi);
    hw_read_row(cursor_y, &lo, &hi);
    draw_cell(cursor_x, cursor_y, lo, hi);
}

/* ── Callbacks ───────────────────────────────────────────────────── */

static void init(void) {
    hw_clear();
    hw_randomize(0xA59B);
    edit_mode = 1;
    cursor_x = 40;
    cursor_y = 12;
    frame_count = 0;
    speed_ms = 200;

    vga_clear();
    vga_goto(0, 2);
    vga_putc('+', VGA_WHITE);
    for (int x = 0; x < 78; x++) vga_putc('-', VGA_WHITE);
    vga_putc('+', VGA_WHITE);
    for (int y = 0; y < 25; y++) {
        vga_goto(0, y + 3); vga_putc('|', VGA_WHITE);
        vga_goto(79, y + 3); vga_putc('|', VGA_WHITE);
    }
    vga_goto(0, 28);
    vga_putc('+', VGA_WHITE);
    for (int x = 0; x < 78; x++) vga_putc('-', VGA_WHITE);
    vga_putc('+', VGA_WHITE);

    initialized = 1;
    draw_grid();
    draw_hud();
}

static void update(void) {
    if (!initialized) return;
    if (++frame_count < speed_ms / 10) return;
    frame_count = 0;

    if (!edit_mode) {
        hw_step();
        draw_grid();
        draw_hud();
    }
}

static void input(char c) {
    if (!initialized) return;

    switch (c) {
        case '\r': case '\n':
            edit_mode = !edit_mode;
            draw_grid();
            break;
        case ' ':
            break;
        case 'r': case 'R':
            hw_randomize(0xDEAD);
            draw_grid();
            break;
        case 'c': case 'C':
            hw_clear();
            draw_grid();
            break;
        case 'w': case 'W': move_cursor(0, -1); break;
        case 's': case 'S': move_cursor(0, 1); break;
        case 'a': case 'A': move_cursor(-1, 0); break;
        case 'd': case 'D': move_cursor(1, 0); break;
        case '+': case '=': case ']':
            if (speed_ms < 1000) speed_ms += 50;
            break;
        case '-': case '[':
            if (speed_ms > 50) speed_ms -= 50;
            break;
        default: {
            uint8_t k = (uint8_t)c;
            if (k == PS2_VK_UP)    { move_cursor(0, -1); }
            else if (k == PS2_VK_DOWN)  { move_cursor(0, 1); }
            else if (k == PS2_VK_LEFT)  { move_cursor(-1, 0); }
            else if (k == PS2_VK_RIGHT) { move_cursor(1, 0); }
            else return;
            break;
        }
    }
    draw_hud();
}

static int finish(void) { return !initialized; }

const program_t prog_conway_hw = {
    "ConwayHW", "Hardware Conway — FPGA-accelerated 80x25 grid",
    init, update, input, NULL, finish
};
