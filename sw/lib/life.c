/* life.c — Conway's Game of Life for de2shell
 * Adapted from sw/app/game_life/main.c
 */
#include "board_status.h"
#include "vga_hal.h"
#include "ps2_decoder.h"
#include <stdint.h>

#define GRID_W 40
#define GRID_H 20

typedef unsigned char cell_t;
static cell_t cur[GRID_H][GRID_W]
#ifdef DE2SHELL_RTOS
    __attribute__((section(".sdram_bss")))
#endif
    ;
static cell_t nxt[GRID_H][GRID_W]
#ifdef DE2SHELL_RTOS
    __attribute__((section(".sdram_bss")))
#endif
    ;
static int gen;
static int initialized;
static int frame_count;
static int speed_ms = 150;
static int edit_mode;
static int cursor_x;
static int cursor_y;

/* ── RNG ──────────────────────────────────────────────────────── */
static unsigned rng = 0x12345678;
static int rng_rand(void) {
    rng = rng * 1103515245u + 12345u;
    return (int)(rng >> 16);
}

/* ── Patterns ──────────────────────────────────────────────────── */
static void grid_clear(void) {
    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++)
            cur[y][x] = 0;
    gen = 0;
}

static void place(int ox, int oy, const char *pat, int pw, int ph) {
    for (int y = 0; y < ph; y++)
        for (int x = 0; x < pw; x++)
            if (pat[y * pw + x] == 'O')
                cur[(oy + y) % GRID_H][(ox + x) % GRID_W] = 1;
}

static void grid_glider(void) {
    grid_clear();
    const char *g = ".O...O.OOO";
    place(GRID_W/2 - 1, GRID_H/2 - 1, g, 3, 3);
}

static void grid_gun(void) {
    grid_clear();
    const char *p =
        "........................O..........."
        "......................O.O..........."
        "............OO......OO............OO"
        "...........O...O....OO............OO"
        "OO........O.....O...OO.............."
        "OO........O...O.OO....O.O..........."
        "..........O.....O.......O..........."
        "...........O...O...................."
        "............OO......................";
    place(2, 4, p, 36, 9);
}

static void grid_random(void) {
    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++)
            cur[y][x] = (rng_rand() & 0x7FFF) < 8192;
    gen = 0;
}

/* ── B3/S23 ────────────────────────────────────────────────────── */
static int neighbors(int x, int y) {
    int count = 0;
    for (int dy = -1; dy <= 1; dy++)
        for (int dx = -1; dx <= 1; dx++) {
            if (!dx && !dy) continue;
            count += cur[(y + dy + GRID_H) % GRID_H]
                        [(x + dx + GRID_W) % GRID_W];
        }
    return count;
}

static void step(void) {
    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++) {
            int n = neighbors(x, y);
            if (cur[y][x]) nxt[y][x] = (n == 2 || n == 3);
            else           nxt[y][x] = (n == 3);
        }
    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++)
            cur[y][x] = nxt[y][x];
    gen++;
}

static void draw_cell(int x, int y) {
    char ch = cur[y][x] ? '#' : '.';
    uint16_t color = cur[y][x] ? VGA_WHITE : VGA_DKGRAY;
    if (edit_mode && x == cursor_x && y == cursor_y) {
        ch = cur[y][x] ? 'O' : '+';
        color = VGA_YELLOW;
    }
    vga_goto(x + 1, y + 3);
    vga_putc(ch, color);
}

static void move_cursor(int dx, int dy) {
    int old_x = cursor_x, old_y = cursor_y;
    cursor_x = (cursor_x + dx + GRID_W) % GRID_W;
    cursor_y = (cursor_y + dy + GRID_H) % GRID_H;
    draw_cell(old_x, old_y);
    draw_cell(cursor_x, cursor_y);
}

static void draw_grid(void) {
    for (int y = 0; y < GRID_H; y++) {
        vga_goto(1, y + 3);
        for (int x = 0; x < GRID_W; x++) {
            char ch = cur[y][x] ? '#' : '.';
            uint16_t color = cur[y][x] ? VGA_WHITE : VGA_DKGRAY;

            if (edit_mode && x == cursor_x && y == cursor_y) {
                ch = cur[y][x] ? 'O' : '+';
                color = VGA_YELLOW;
            }
            vga_putc(ch, color);
        }
    }
}

static void draw_hud(void) {
    char buf[7];
    int g = gen;
    int speed = speed_ms;
    uint8_t state = edit_mode ? BOARD_STATE_EDIT : BOARD_STATE_RUN;

    for (int i = 5; i >= 0; i--) {
        buf[i] = (char)('0' + (g % 10));
        g /= 10;
    }
    buf[6] = 0;

    board_status_set_program(5u, state, (uint8_t)(cur[cursor_y][cursor_x] ? 1u : 0u),
                             (uint16_t)(((cursor_y & 0xffu) << 8) | (cursor_x & 0xffu)));

    vga_goto(0, 0);
    vga_puts("Conway  Gen:", VGA_CYAN);
    vga_puts(buf, VGA_YELLOW);
    vga_puts(edit_mode ? "  STOP " : "  RUN  ", VGA_WHITE);
    vga_puts("SPD:", VGA_WHITE);
    if (speed >= 100) {
        vga_putc((char)('0' + ((speed / 100) % 10)), VGA_YELLOW);
    } else {
        vga_putc(' ', VGA_YELLOW);
    }
    vga_putc((char)('0' + ((speed / 10) % 10)), VGA_YELLOW);
    vga_putc((char)('0' + (speed % 10)), VGA_YELLOW);
    vga_putc(' ', VGA_WHITE);
    vga_puts("X:", VGA_WHITE);
    vga_puthex32((uint32_t)cursor_x);
    vga_puts(" Y:", VGA_WHITE);
    vga_puthex32((uint32_t)cursor_y);

    vga_goto(0, 1);
    vga_puts("Arrows/WASD move  SPACE toggle  ENTER start/stop  [/ ] or +/- speed  G/N/R/C pattern  Q quit",
             VGA_GRAY);
}

/* ═══════════════════════════════════════════════════════════════
   Shell Callbacks
   ═══════════════════════════════════════════════════════════════ */

static void init(void) {
    grid_glider();
    speed_ms = 150;
    frame_count = 0;
    edit_mode = 1;
    cursor_x = GRID_W / 2;
    cursor_y = GRID_H / 2;

    /* Draw border once */
    vga_clear();
    vga_goto(0, 2);
    vga_putc('+', VGA_WHITE);
    for (int x = 0; x < GRID_W; x++) vga_putc('-', VGA_WHITE);
    vga_putc('+', VGA_WHITE);
    for (int y = 0; y < GRID_H; y++) {
        vga_goto(0, y + 3); vga_putc('|', VGA_WHITE);
        vga_goto(GRID_W + 1, y + 3); vga_putc('|', VGA_WHITE);
    }
    vga_goto(0, GRID_H + 3);
    vga_putc('+', VGA_WHITE);
    for (int x = 0; x < GRID_W; x++) vga_putc('-', VGA_WHITE);
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
        step();
        draw_grid();
        draw_hud();
    }
}

static void input(char c) {
    switch (c) {
        case '\r': case '\n':
            edit_mode = !edit_mode;
            draw_grid();
            break;
        case ' ':
            if (edit_mode) {
                cur[cursor_y][cursor_x] = (cell_t)!cur[cursor_y][cursor_x];
                draw_cell(cursor_x, cursor_y);
            }
            break;
        case 'g': case 'G':
            grid_glider();
            edit_mode = 1;
            draw_grid();
            break;
        case 'n': case 'N':
            grid_gun();
            edit_mode = 1;
            draw_grid();
            break;
        case 'r': case 'R':
            grid_random();
            edit_mode = 1;
            draw_grid();
            break;
        case 'c': case 'C':
            grid_clear();
            edit_mode = 1;
            draw_grid();
            break;
        case 'w': case 'W': move_cursor(0, -1); break;
        case 's': case 'S': move_cursor(0, 1); break;
        case 'a': case 'A': move_cursor(-1, 0); break;
        case 'd': case 'D': move_cursor(1, 0); break;
        case '+': case '=': case ']': case '.':
            if (speed_ms < 500) speed_ms += 10;
            break;
        case '-': case '_': case '[': case ',':
            if (speed_ms > 20) speed_ms -= 10;
            break;
        default: {
            uint8_t k = (uint8_t)c;
            if (k == PS2_VK_UP)       { move_cursor(0, -1); }
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

const program_t prog_life = {
    "ConwayLife", "Conway Game of Life — edit/run modes",
    init, update, input, NULL, finish
};
