/* conway_hw.c — Hardware-accelerated Conway's Game of Life (64x25)
 *
 * FPGA conway_engine at 0xF0011000.  CPU reads grid rows via 2-word MMIO
 * and writes to VGA text terminal.
 *
 * Layout (vga_goto col, row):
 *   R0  : HUD  (left: Gen/Pop  right: RUN/STOP  far-right: F1=Help)
 *   R1  : +---------------------------------------------------------------+  C1..C66
 *   R2  : | <64 cells>                                                  |  C2..C65
 *   ...
 *   R26 : | <64 cells>                                                  |
 *   R27 : +---------------------------------------------------------------+  C1..C66
 *   R28 : (empty)
 *   R29 : system status bar
 *
 * Registers:
 *   0x00 [W] cmd: bit0=clear, bit1=randomize, bit2=step, bit3=auto_run, bit4=toggle_cell
 *   0x04 [W] control: bits[12:8]=row_index, bits[6:0]=col_index
 *   0x08 [R] status: bit0=busy, bit1=auto_run, bits[17:2]=generation
 *   0x0C [R] population [15:0]
 *   0x10 [R] grid_row lo:  cols 0-31
 *   0x14 [R] grid_row mid: cols 32-63
 */
#include "board_status.h"
#include "vga_hal.h"
#include "ps2_decoder.h"
#include <stdint.h>
#ifndef LOCAL_BUILD
#include <neorv32.h>
#endif

#define CONWAY_BASE  ((volatile uint32_t *)0xF0011000u)

#define CONWAY_CMD      (*(CONWAY_BASE + 0))
#define CONWAY_CTRL     (*(CONWAY_BASE + 1))
#define CONWAY_STATUS   (*(CONWAY_BASE + 2))
#define CONWAY_POP      (*(CONWAY_BASE + 3))
#define CONWAY_GRID_LO  (*(CONWAY_BASE + 4))
#define CONWAY_GRID_MID (*(CONWAY_BASE + 5))

static int initialized;
static int help_open;
static int edit_mode;
static int cursor_x, cursor_y;
static int frame_count;
static int speed_ms = 200;  /* ms per generation step */

/* Shadow buffer for partial refresh */
static uint32_t prev_lo[25], prev_mid[25];
static uint16_t prev_gen, prev_pop;
static int prev_edit, prev_gps;
static uint32_t seed_fallback = 0x13579BDFu;

/* ── Hardware helpers ────────────────────────────────────────────── */

static void hw_set_row(int row) {
    CONWAY_CTRL = (uint32_t)((row & 0x1F) << 8);
}

static void hw_read_row(int row, uint32_t *lo, uint32_t *mid) {
    hw_set_row(row);
    *lo = CONWAY_GRID_LO;
    *mid = CONWAY_GRID_MID;
}

#define HW_TIMEOUT 1000000

static int hw_busy(void) { return (int)(CONWAY_STATUS & 1u); }

static int hw_wait(int timeout) {
    while (timeout-- > 0 && hw_busy()) {}
    return timeout <= 0;
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

static int hw_toggle_cell(int row, int col) {
    CONWAY_CTRL = (uint32_t)((row & 0x1F) << 8) | (col & 0x3F);
    CONWAY_CMD = 16u;
    return hw_wait(HW_TIMEOUT);
}

static uint16_t next_seed(void) {
#ifdef LOCAL_BUILD
    seed_fallback = seed_fallback * 1103515245u + 12345u;
    return (uint16_t)(seed_fallback >> 16);
#else
    if (neorv32_trng_available()) {
        uint16_t seed = 0;
        int timeout;

        neorv32_trng_enable();
        neorv32_trng_fifo_clear();

        for (int i = 0; i < 2; i++) {
            timeout = 200000;
            while (!neorv32_trng_data_avail() && --timeout > 0) {}
            if (timeout <= 0) {
                break;
            }
            seed = (uint16_t)((seed << 8) | neorv32_trng_data_get());
        }
        if (seed != 0) {
            return seed;
        }
    }

    seed_fallback = seed_fallback * 1103515245u + 12345u;
    return (uint16_t)(seed_fallback >> 16);
#endif
}

/* ── Display ──────────────────────────────────────────────────────── */

static void put_dec(uint32_t v, uint16_t color) {
    char buf[10];
    int pos = 0;
    if (v == 0) { vga_putc('0', color); return; }
    while (v > 0) { buf[pos++] = '0' + (v % 10); v /= 10; }
    for (int i = pos - 1; i >= 0; i--) vga_putc(buf[i], color);
}

static int cell_bit(int x, uint32_t lo, uint32_t mid) {
    if (x < 32) return (int)((lo >> x) & 1u);
    return (int)((mid >> (x - 32)) & 1u);
}

/* cell(x,y) → VGA col=x+2, row=y+2. edit_mode: cursor shows +/O */
static void draw_cell(int x, int y, int bit, int show_cursor) {
    char ch;
    uint16_t color;
    if (show_cursor && edit_mode) {
        ch = bit ? 'O' : '+';
        color = VGA_YELLOW;
    } else {
        ch = bit ? '#' : '.';
        color = bit ? VGA_WHITE : VGA_DKGRAY;
    }
    vga_goto(x + 2, y + 2);
    vga_putc(ch, color);
}

static void refresh_row(int y, int force) {
    uint32_t lo, mid;
    hw_read_row(y, &lo, &mid);
    if (!force && lo == prev_lo[y] && mid == prev_mid[y]) {
        return;
    }

    for (int x = 0; x < 64; x++) {
        int bit = cell_bit(x, lo, mid);
        int prev_bit = cell_bit(x, prev_lo[y], prev_mid[y]);
        if (force || bit != prev_bit) {
            draw_cell(x, y, bit, 0);
        }
    }
    prev_lo[y] = lo;
    prev_mid[y] = mid;
}

static void draw_grid(void) {
    for (int y = 0; y < 25; y++) {
        refresh_row(y, 1);
    }
}

/* Partial refresh: redraw only cells that changed */
static void draw_grid_partial(void) {
    for (int y = 0; y < 25; y++) {
        refresh_row(y, 0);
    }
}

static void draw_hud(void) {
    uint16_t gen = hw_generation();
    uint16_t pop = hw_population();
    int gps = (speed_ms > 0) ? 1000 / speed_ms : 0;
    uint8_t state = edit_mode ? BOARD_STATE_EDIT : BOARD_STATE_RUN;

    board_status_set_program(10u, state, 0u,
                             (uint16_t)(((cursor_y & 0xffu) << 8) | (cursor_x & 0xffu)));

    /* Only redraw HUD if values changed */
    if (gen != prev_gen || pop != prev_pop || edit_mode != prev_edit || gps != prev_gps) {
        vga_goto(0, 0);
        vga_puts("Gen:", VGA_CYAN);
        put_dec(gen, VGA_CYAN);
        vga_puts(" Pop:", VGA_WHITE);
        put_dec(pop, VGA_WHITE);
        vga_puts(" GPS:", VGA_WHITE);
        put_dec((uint32_t)gps, VGA_WHITE);

        vga_goto(60, 0);
        vga_puts(edit_mode ? " STOP " : " RUN  ", VGA_YELLOW);
        vga_goto(66, 0);
        vga_puts("F1=Help", VGA_GRAY);

        prev_gen = gen;
        prev_pop = pop;
        prev_edit = edit_mode;
        prev_gps = gps;
    }
}

static void draw_border(void) {
    /* top: R1 */
    vga_goto(1, 1);
    vga_putc('+', VGA_WHITE);
    for (int x = 0; x < 64; x++) vga_putc('-', VGA_WHITE);
    vga_putc('+', VGA_WHITE);
    /* sides: R2-R26 */
    for (int y = 0; y < 25; y++) {
        vga_goto(1, y + 2);  vga_putc('|', VGA_WHITE);
        vga_goto(66, y + 2); vga_putc('|', VGA_WHITE);
    }
    /* bottom: R27 */
    vga_goto(1, 27);
    vga_putc('+', VGA_WHITE);
    for (int x = 0; x < 64; x++) vga_putc('-', VGA_WHITE);
    vga_putc('+', VGA_WHITE);
}

static void move_cursor(int dx, int dy) {
    int old_x = cursor_x, old_y = cursor_y;
    uint32_t lo, mid;

    cursor_x = (cursor_x + dx + 64) % 64;
    cursor_y = (cursor_y + dy + 25) % 25;

    if (edit_mode) {
        hw_read_row(old_y, &lo, &mid);
        draw_cell(old_x, old_y, cell_bit(old_x, lo, mid), 0);
        hw_read_row(cursor_y, &lo, &mid);
        draw_cell(cursor_x, cursor_y, cell_bit(cursor_x, lo, mid), 1);
    }
}

/* ── Callbacks ───────────────────────────────────────────────────── */

static void init(void) {
    hw_clear();
    edit_mode = 1;
    cursor_x = 32;
    cursor_y = 12;
    frame_count = 0;
    speed_ms = 200;

    /* Clear shadow buffer to force first full draw */
    for (int i = 0; i < 25; i++) { prev_lo[i] = 0xFFFFFFFFu; prev_mid[i] = 0xFFFFFFFFu; }
    prev_gen = 0xFFFFu; prev_pop = 0xFFFFu; prev_edit = -1; prev_gps = -1;

    vga_clear();
    vga_cursor_show(0);
    draw_border();

    initialized = 1;
    draw_grid();
    draw_hud();
    move_cursor(0, 0);
}

static void update(void) {
    if (!initialized || help_open) return;
    if (++frame_count < speed_ms / 10) return;
    frame_count = 0;

    if (!edit_mode) {
        hw_step();
        draw_grid_partial();
        draw_hud();
    }
}

/* ── Help Overlay ──────────────────────────────────────────────── */

static void draw_help(void) {
    int bx = 4, by = 4, bw = 60, bh = 22;

    /* background */
    for (int r = by; r < by + bh; r++) {
        vga_goto(bx, r);
        for (int c = 0; c < bw; c++) vga_putc(' ', VGA_BLACK);
    }
    /* box */
    vga_goto(bx, by);
    vga_putc('+', VGA_YELLOW);
    for (int i = 0; i < bw - 2; i++) vga_putc('-', VGA_YELLOW);
    vga_putc('+', VGA_YELLOW);
    vga_goto(bx, by + bh - 1);
    vga_putc('+', VGA_YELLOW);
    for (int i = 0; i < bw - 2; i++) vga_putc('-', VGA_YELLOW);
    vga_putc('+', VGA_YELLOW);
    for (int r = by + 1; r < by + bh - 1; r++) {
        vga_goto(bx, r);           vga_putc('|', VGA_YELLOW);
        vga_goto(bx + bw - 1, r); vga_putc('|', VGA_YELLOW);
    }

    /* title */
    vga_goto(bx + 20, by + 1);
    vga_puts("CONWAY'S GAME OF LIFE", VGA_CYAN);

    /* rules */
    vga_goto(bx + 2, by + 3);
    vga_puts("Rules (B3/S23, toroidal wrap):", VGA_WHITE);
    vga_goto(bx + 4, by + 4);
    vga_puts("Live  cell + 2 or 3 neighbors -> survives", VGA_WHITE);
    vga_goto(bx + 4, by + 5);
    vga_puts("Dead  cell + exactly 3 neighbors -> born", VGA_WHITE);
    vga_goto(bx + 4, by + 6);
    vga_puts("All other cells die or stay dead", VGA_WHITE);

    /* controls */
    vga_goto(bx + 2, by + 8);
    vga_puts("Controls:", VGA_CYAN);
    vga_goto(bx + 4, by + 9);
    vga_puts("Arrows / WASD : Move cursor", VGA_WHITE);
    vga_goto(bx + 4, by + 10);
    vga_puts("Space          : Toggle cell (edit mode)", VGA_WHITE);
    vga_goto(bx + 4, by + 11);
    vga_puts("Enter          : Run / Stop simulation", VGA_WHITE);
    vga_goto(bx + 4, by + 12);
    vga_puts("+ / -          : Speed up / slow down", VGA_WHITE);
    vga_goto(bx + 4, by + 13);
    vga_puts("R              : Randomize grid", VGA_WHITE);
    vga_goto(bx + 4, by + 14);
    vga_puts("C              : Clear grid", VGA_WHITE);

    vga_goto(bx + 2, by + 16);
    vga_puts("F1  : Close this help", VGA_GRAY);
    vga_goto(bx + 2, by + 17);
    vga_puts("F10 : Quit to shell", VGA_GRAY);
}

static void input(char c) {
    if (!initialized) return;
    uint8_t k = (uint8_t)c;

    if (k == PS2_VK_F1) {
        help_open = !help_open;
        if (help_open) draw_help();
        else { draw_grid(); draw_hud(); }
        return;
    }
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
            break;
        case ' ':
            if (edit_mode) {
                if (!hw_toggle_cell(cursor_y, cursor_x)) {
                    refresh_row(cursor_y, 0);
                }
            }
            break;
        case 'r': case 'R':
            hw_randomize(next_seed());
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
            if (speed_ms > 50) speed_ms -= 50;
            break;
        case '-': case '[':
            if (speed_ms < 2000) speed_ms += 50;
            break;
        default:
            if (k == PS2_VK_UP)         move_cursor(0, -1);
            else if (k == PS2_VK_DOWN)   move_cursor(0, 1);
            else if (k == PS2_VK_LEFT)   move_cursor(-1, 0);
            else if (k == PS2_VK_RIGHT)  move_cursor(1, 0);
            else return;
            break;
    }
    draw_hud();
}

static int finish(void) {
    if (!initialized) return 1;
    return 0;
}

const program_t prog_conway = {
    "Conway", "Hardware Conway — FPGA-accelerated 64x25 grid",
    init, update, input, NULL, finish
};
