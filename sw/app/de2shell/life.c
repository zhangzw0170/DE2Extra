/* life.c — Conway's Game of Life for de2shell
 * Adapted from sw/app/game_life/main.c
 */
#include "board_status.h"
#include "vga_hal.h"
#include <stdint.h>

#define GRID_W 40
#define GRID_H 20

typedef unsigned char cell_t;
static cell_t cur[GRID_H][GRID_W];
static cell_t nxt[GRID_H][GRID_W];
static int gen;
static int paused;
static int initialized;
static int frame_count;
static int speed_ms = 150;
static int edit_mode;
static int cursor_x;
static int cursor_y;
static int esc_state;

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
        "................................O..........."
        "..............................O.O..........."
        "....................OO......OO............OO"
        "...................O...O....OO............OO"
        "........OO........O.....O...OO.............."
        "........OO........O...O.OO....O.O..........."
        "..................O.....O.......O..........."
        "...................O...O...................."
        "....................OO......................";
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

static void move_cursor(int dx, int dy) {
    cursor_x = (cursor_x + dx + GRID_W) % GRID_W;
    cursor_y = (cursor_y + dy + GRID_H) % GRID_H;
}

static void draw_grid(void) {
    for (int y = 0; y < GRID_H; y++) {
        vga_goto(1, y + 3);
        for (int x = 0; x < GRID_W; x++) {
            char ch = cur[y][x] ? '\xDB' : ' ';
            uint8_t color = cur[y][x] ? VGA_GREEN : VGA_BLACK;

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
    uint8_t state = BOARD_STATE_RUN;

    for (int i = 5; i >= 0; i--) {
        buf[i] = (char)('0' + (g % 10));
        g /= 10;
    }
    buf[6] = 0;

    if (edit_mode) {
        state = BOARD_STATE_EDIT;
    } else if (paused) {
        state = BOARD_STATE_HOLD;
    }
    board_status_set_program(6u, state, (uint8_t)(cur[cursor_y][cursor_x] ? 1u : 0u),
                             (uint16_t)(((cursor_y & 0xffu) << 8) | (cursor_x & 0xffu)));

    vga_goto(0, 0);
    vga_puts("Conway  Gen:", VGA_CYAN);
    vga_puts(buf, VGA_YELLOW);
    vga_puts(edit_mode ? "  EDIT " : (paused ? "  HOLD " : "  RUN  "), VGA_WHITE);
    vga_puts("X:", VGA_WHITE);
    vga_puthex32((uint32_t)cursor_x);
    vga_puts(" Y:", VGA_WHITE);
    vga_puthex32((uint32_t)cursor_y);

    vga_goto(0, 1);
    vga_puts("Arrows/WASD move  SPACE toggle/step  ENTER run  E edit  G/N/R/C pattern  Q quit",
             VGA_GRAY);
}

/* ═══════════════════════════════════════════════════════════════
   Shell Callbacks
   ═══════════════════════════════════════════════════════════════ */

static void init(void) {
    grid_glider();
    paused = 1;
    speed_ms = 150;
    frame_count = 0;
    edit_mode = 1;
    cursor_x = GRID_W / 2;
    cursor_y = GRID_H / 2;
    esc_state = 0;

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

    if (!edit_mode && !paused) {
        step();
        draw_grid();
        draw_hud();
    }
}

static void input(char c) {
    if (esc_state == 1) {
        esc_state = (c == '[') ? 2 : 0;
        return;
    }
    if (esc_state == 2) {
        if (c == 'A') move_cursor(0, -1);
        else if (c == 'B') move_cursor(0, 1);
        else if (c == 'C') move_cursor(1, 0);
        else if (c == 'D') move_cursor(-1, 0);
        esc_state = 0;
        draw_grid();
        draw_hud();
        return;
    }
    if (c == 27) {
        esc_state = 1;
        return;
    }

    switch (c) {
        case 'q': case 'Q': initialized = 0; return;
        case '\r': case '\n':
            edit_mode = 0;
            paused = 0;
            break;
        case 'e': case 'E':
            edit_mode = 1;
            paused = 1;
            break;
        case ' ':
            if (edit_mode) {
                cur[cursor_y][cursor_x] = (cell_t)!cur[cursor_y][cursor_x];
            } else if (paused) {
                step();
            }
            break;
        case 'p': case 'P':
            if (!edit_mode) {
                paused = !paused;
            }
            break;
        case 'g': case 'G':
            grid_glider();
            edit_mode = 1;
            paused = 1;
            break;
        case 'n': case 'N':
            grid_gun();
            edit_mode = 1;
            paused = 1;
            break;
        case 'r': case 'R':
            grid_random();
            edit_mode = 1;
            paused = 1;
            break;
        case 'c': case 'C':
            grid_clear();
            edit_mode = 1;
            paused = 1;
            break;
        case 'w': case 'W': move_cursor(0, -1); break;
        case 's': case 'S': move_cursor(0, 1); break;
        case 'a': case 'A': move_cursor(-1, 0); break;
        case 'd': case 'D': move_cursor(1, 0); break;
        case '+': case '=': if (speed_ms > 20) speed_ms -= 10; break;
        case '-': case '_': if (speed_ms < 500) speed_ms += 10; break;
        default: return;
    }
    draw_grid();
    draw_hud();
}

static int finish(void) { return !initialized; }

const program_t prog_life = {
    "Life", "Conway Game of Life — edit/run modes",
    init, update, input, NULL, finish
};
