/* conway_hw.c — Hardware-accelerated Conway's Game of Life
 *
 * Uses FPGA conway_engine at 0xF0011000 for grid computation.
 * CPU reads grid rows via MMIO and writes to VGA text terminal.
 *
 * Registers:
 *   0x00 [W] cmd: bit0=clear, bit1=randomize, bit2=step, bit3=auto_run, bit4=toggle_cell
 *   0x04 [W] control: bits[15:8]=row_index, bits[6:0]=col_index (for toggle)
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
#define CONWAY_GRID_LO   (*(CONWAY_BASE + 4))  /* R, cols 0-31 */
#define CONWAY_GRID_MID  (*(CONWAY_BASE + 5))  /* R, cols 32-63 */
#define CONWAY_GRID_HI2  (*(CONWAY_BASE + 6))  /* R, cols 64-79 */

static int initialized;
static int help_open;
static int edit_mode;
static int cursor_x, cursor_y;
static int frame_count;
static int speed_ms = 200;

/* ── Hardware helpers ────────────────────────────────────────────── */

static void hw_set_row(int row) {
    CONWAY_CTRL = (uint32_t)((row & 0x1F) << 8);
}

static void hw_read_row(int row, uint32_t *lo, uint32_t *mid, uint32_t *hi) {
    hw_set_row(row);
    *lo = CONWAY_GRID_LO;
    *mid = CONWAY_GRID_MID;
    *hi = CONWAY_GRID_HI2;
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

static void hw_toggle_cell(int row, int col) {
    CONWAY_CTRL = (uint32_t)((row & 0x1F) << 8) | (col & 0x7F);
    CONWAY_CMD = 16u;
}

/* ── Display ──────────────────────────────────────────────────────── */

static int cell_bit(int x, uint32_t lo, uint32_t mid, uint32_t hi) {
    if (x < 32) return (int)((lo >> x) & 1u);
    if (x < 64) return (int)((mid >> (x - 32)) & 1u);
    return (int)((hi >> (x - 64)) & 1u);
}

static void draw_cell(int x, int y, uint32_t lo, uint32_t mid, uint32_t hi) {
    int bit = cell_bit(x, lo, mid, hi);
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
        uint32_t lo, mid, hi;
        hw_read_row(y, &lo, &mid, &hi);

        vga_goto(1, y + 3);
        for (int x = 0; x < CONWAY_DISP_COLS; x++) {
            int bit = cell_bit(x, lo, mid, hi);
            char ch = bit ? '#' : '.';
            uint16_t color = bit ? VGA_WHITE : VGA_DKGRAY;
            if (edit_mode && x == cursor_x && y == cursor_y) {
                ch = bit ? 'O' : '+';
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
    vga_puts("Conway Gen:", VGA_CYAN);
    vga_puthex32(gen);
    vga_puts(" Pop:", VGA_WHITE);
    vga_puthex32(pop);
    vga_puts(" ", VGA_WHITE);
    vga_puts(edit_mode ? "STOP" : "RUN ", VGA_YELLOW);
    vga_puts(" SPD:", VGA_WHITE);
    vga_puthex32((uint32_t)speed_ms);
    vga_goto(70, 0);
    vga_puts("F1=Help", VGA_GRAY);
}

static void move_cursor(int dx, int dy) {
    int old_x = cursor_x, old_y = cursor_y;
    cursor_x = (cursor_x + dx + 80) % 80;
    cursor_y = (cursor_y + dy + 25) % 25;
    /* Redraw only old and new cell */
    uint32_t lo, mid, hi;
    hw_read_row(old_y, &lo, &mid, &hi);
    draw_cell(old_x, old_y, lo, mid, hi);
    hw_read_row(cursor_y, &lo, &mid, &hi);
    draw_cell(cursor_x, cursor_y, lo, mid, hi);
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
    if (!initialized || help_open) return;
    if (++frame_count < speed_ms / 10) return;
    frame_count = 0;

    if (!edit_mode) {
        hw_step();
        draw_grid();
        draw_hud();
    }
}

/* ── Help Overlay ──────────────────────────────────────────────── */

static void draw_help(void) {
    int bx = 18, by = 5, bw = 44, bh = 18;

    for (int r = by; r < by + bh; r++) {
        vga_goto(bx, r);
        for (int c = 0; c < bw; c++) vga_putc(' ', VGA_BLACK);
    }
    vga_goto(bx, by);
    vga_putc('+', VGA_YELLOW);
    for (int i = 0; i < bw - 2; i++) vga_putc('-', VGA_YELLOW);
    vga_putc('+', VGA_YELLOW);
    vga_goto(bx, by + bh - 1);
    vga_putc('+', VGA_YELLOW);
    for (int i = 0; i < bw - 2; i++) vga_putc('-', VGA_YELLOW);
    vga_putc('+', VGA_YELLOW);
    for (int r = by + 1; r < by + bh - 1; r++) {
        vga_goto(bx, r); vga_putc('|', VGA_YELLOW);
        vga_goto(bx + bw - 1, r); vga_putc('|', VGA_YELLOW);
    }

    vga_goto(bx + 13, by + 1);
    vga_puts("CONWAY HELP", VGA_CYAN);

    vga_goto(bx + 2, by + 3);
    vga_puts("Arrows/WASD: Move cursor", VGA_WHITE);
    vga_goto(bx + 2, by + 4);
    vga_puts("Space: Toggle cell (edit mode)", VGA_WHITE);
    vga_goto(bx + 2, by + 5);
    vga_puts("Enter: Run/Stop simulation", VGA_WHITE);
    vga_goto(bx + 2, by + 7);
    vga_puts("R: Randomize grid", VGA_WHITE);
    vga_goto(bx + 2, by + 8);
    vga_puts("C: Clear grid", VGA_WHITE);
    vga_goto(bx + 2, by + 9);
    vga_puts("+/-: Adjust speed", VGA_WHITE);
    vga_goto(bx + 2, by + 11);
    vga_puts("F1:  Close help", VGA_GRAY);
    vga_goto(bx + 2, by + 12);
    vga_puts("F10: Quit to shell", VGA_GRAY);
}

static void input(char c) {
    if (!initialized) return;
    uint8_t k = (uint8_t)c;

    /* F1: toggle help */
    if (k == PS2_VK_F1) {
        help_open = !help_open;
        if (help_open) draw_help();
        else { draw_grid(); draw_hud(); }
        return;
    }
    /* F10: close help or quit */
    if (k == PS2_VK_F10) {
        if (help_open) {
            help_open = 0;
            draw_grid(); draw_hud();
            return;
        }
        initialized = 0;
        return;
    }

    if (help_open) return;

    switch (c) {
        case '\r': case '\n':
            edit_mode = !edit_mode;
            draw_grid();
            break;
        case ' ':
            if (edit_mode) {
                hw_toggle_cell(cursor_y, cursor_x);
                draw_grid();
            }
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

const program_t prog_conway = {
    "Conway", "Hardware Conway — FPGA-accelerated 80x25 grid",
    init, update, input, NULL, finish
};
