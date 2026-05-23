/* conway_ed.c — Conway Editor + Simulation for de2shell
 *
 * WASD/arrows: move cursor
 * SPACE: toggle cell at cursor
 * ENTER: run simulation
 * ESC: return to shell
 *
 * LOCAL_BUILD: pure software Conway (from game_life logic)
 * NEORV32: hardware engine via conway_engine.vhd registers
 */

#include "vga_hal.h"
#include <stdint.h>

#define GRID_W 80
#define GRID_H 25

typedef unsigned char cell_t;
static cell_t cur[GRID_H][GRID_W];
static cell_t nxt[GRID_H][GRID_W];
static int gen, paused, running, editing;
static int cx, cy;  /* cursor position */
static int mode;    /* 0=edit, 1=simulate */
static int active;
static int frame_count;

/* ── Drawing ──────────────────────────────────────────────────── */

static void draw_grid(void) {
    for (int y = 0; y < GRID_H; y++) {
        vga_goto(0, y);
        for (int x = 0; x < GRID_W; x++) {
            char ch = cur[y][x] ? '#' : '.';
            int color = cur[y][x] ? VGA_GREEN : VGA_GRAY;
            if (editing && x == cx && y == cy) {
                ch = cur[y][x] ? 'O' : '+';
                color = VGA_YELLOW;
            }
            vga_putc(ch, color);
        }
    }
}

static void draw_hud(void) {
    vga_goto(0, GRID_H);
    vga_puts("Conway  Gen:", VGA_CYAN);
    vga_puthex32(gen);
    vga_puts(mode ? "  RUNNING  " : "  EDITING  ", mode ? VGA_GREEN : VGA_BLUE);
    vga_puts("X:", VGA_WHITE); vga_puthex32(cx);
    vga_puts(" Y:", VGA_WHITE); vga_puthex32(cy);
    vga_puts("  SPACE=toggle  ENTER=run  ESC=quit", VGA_GRAY);
}

/* ── B3/S23 ───────────────────────────────────────────────────── */

static int neighbors(int x, int y) {
    int c = 0;
    for (int dy = -1; dy <= 1; dy++)
        for (int dx = -1; dx <= 1; dx++) {
            if (!dx && !dy) continue;
            int nx = (x + dx + GRID_W) % GRID_W;
            int ny = (y + dy + GRID_H) % GRID_H;
            c += cur[ny][nx];
        }
    return c;
}

static void step(void) {
    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++) {
            int n = neighbors(x, y);
            nxt[y][x] = cur[y][x] ? (n == 2 || n == 3) : (n == 3);
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
    vga_clear();
    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++)
            cur[y][x] = 0;
    gen = 0; paused = 0; running = 1; editing = 1; mode = 0;
    cx = GRID_W / 2; cy = GRID_H / 2;
    frame_count = 0;
    active = 1;
    draw_grid();
    draw_hud();
}

static void update(void) {
    if (!active) return;
    if (++frame_count < 15) return;  /* ~6fps simulation */
    frame_count = 0;

    if (mode == 1 && !paused) {
        step();
        draw_grid();
        draw_hud();
    }
}

static void input(char c) {
    if (!active) return;
    switch (c) {
        case 27: active = 0; return;  /* ESC */
        case '\r': case '\n':  /* ENTER */
            mode = 1; paused = 0;
            draw_grid(); draw_hud();
            break;
        case ' ':
            cur[cy][cx] = !cur[cy][cx];
            if (mode == 1) { /* edit while simulating */
                if (cur[cy][cx]) gen = 0; /* mark as edited */
            }
            draw_grid(); draw_hud();
            break;
        case 'w': case 'W': if (cy > 0) cy--; draw_grid(); draw_hud(); break;
        case 's': case 'S': if (cy < GRID_H-1) cy++; draw_grid(); draw_hud(); break;
        case 'a': case 'A': cx = (cx - 1 + GRID_W) % GRID_W; draw_grid(); draw_hud(); break;
        case 'd': case 'D': cx = (cx + 1) % GRID_W; draw_grid(); draw_hud(); break;
        case 'p': case 'P': paused = !paused; draw_hud(); break;
        case 'c': case 'C':
            for (int y = 0; y < GRID_H; y++)
                for (int x = 0; x < GRID_W; x++)
                    cur[y][x] = 0;
            gen = 0; mode = 0; draw_grid(); draw_hud();
            break;
    }
    if (c == 27) active = 0;
}

static int finish(void) { return !active; }

const program_t prog_conway_ed = {
    "ConwayEd", "Conway Editor — SPACE=toggle ENTER=run ESC=quit",
    init, update, input, NULL, finish
};
