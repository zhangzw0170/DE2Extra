/* life.c — Conway's Game of Life for de2shell
 * Adapted from sw/app/game_life/main.c
 */
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

/* ═══════════════════════════════════════════════════════════════
   Shell Callbacks
   ═══════════════════════════════════════════════════════════════ */

static void init(void) {
    grid_glider();
    paused = 0;
    speed_ms = 150;
    frame_count = 0;

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
}

static void update(void) {
    if (!initialized) return;
    if (++frame_count < speed_ms / 10) return;
    frame_count = 0;

    if (!paused) step();

    /* Draw grid */
    for (int y = 0; y < GRID_H; y++) {
        vga_goto(1, y + 3);
        for (int x = 0; x < GRID_W; x++)
            vga_putc(cur[y][x] ? '\xDB' : ' ', cur[y][x] ? VGA_GREEN : VGA_BLACK);
    }

    /* HUD */
    vga_goto(0, 0);
    vga_puts("Conway  Gen:", VGA_CYAN);
    char buf[7]; int g = gen;
    for (int i = 5; i >= 0; i--) { buf[i] = '0' + g % 10; g /= 10; }
    buf[6] = 0; vga_puts(buf, VGA_YELLOW);

    vga_puts(paused ? " PAUSED" : " RUN  ", VGA_WHITE);
    vga_puts(" SP=step G=gun R=rand C=clear Q=quit", VGA_GRAY);
}

static void input(char c) {
    switch (c) {
        case 'q': case 'Q': initialized = 0; return;
        case ' ': step(); break;
        case 'p': case 'P': paused = !paused; break;
        case 'g': case 'G': grid_glider(); gen = 0; break;
        case 'n': case 'N': grid_gun();     gen = 0; break;
        case 'r': case 'R': grid_random();  gen = 0; break;
        case 'c': case 'C': grid_clear();   gen = 0; break;
        case '+': case '=': if (speed_ms > 20) speed_ms -= 10; break;
        case '-': case '_': if (speed_ms < 500) speed_ms += 10; break;
    }
}

static int finish(void) { return !initialized; }

const program_t prog_life = {
    "Life", "Conway Game of Life — B3/S23, SP=step",
    init, update, input, NULL, finish
};
