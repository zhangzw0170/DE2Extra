/* snake.c — Snake Game for de2shell
 * Adapted from sw/app/game_snake/main.c
 */
#include "vga_hal.h"
#include <stdint.h>

#define GRID_W 40
#define GRID_H 20
#define MAX_SNAKE (GRID_W * GRID_H)

/* ── Game State ───────────────────────────────────────────────── */

static int snake_x[MAX_SNAKE];
static int snake_y[MAX_SNAKE];
static int snake_len;
static int dir_x, dir_y;
static int food_x, food_y;
static int score;
static int game_over;
static int speed_ms;
static int initialized;
static int frame_count;

/* ── RNG ──────────────────────────────────────────────────────── */

static unsigned rng = 0x12345678;
static int rng_range(int max) {
    rng = rng * 1103515245u + 12345u;
    return ((int)(rng >> 16) & 0x7FFFFFFF) % max;
}

/* ── Helpers ──────────────────────────────────────────────────── */

static int food_on_snake(void) {
    for (int i = 0; i < snake_len; i++)
        if (snake_x[i] == food_x && snake_y[i] == food_y) return 1;
    return 0;
}

static void place_food(void) {
    int tries = 0;
    do {
        food_x = rng_range(GRID_W);
        food_y = rng_range(GRID_H);
    } while (++tries < 100 && food_on_snake());
}

/* ═══════════════════════════════════════════════════════════════
   Shell Callbacks
   ═══════════════════════════════════════════════════════════════ */

static void init(void) {
    snake_len = 3;
    int sx = GRID_W / 2, sy = GRID_H / 2;
    for (int i = 0; i < snake_len; i++) {
        snake_x[i] = sx - i; snake_y[i] = sy;
    }
    dir_x = 1; dir_y = 0;
    score = 0;
    game_over = 0;
    speed_ms = 120;
    frame_count = 0;
    place_food();

    vga_clear();
    /* draw border */
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
    if (!initialized || game_over) return;
    if (++frame_count < speed_ms / 10) return;
    frame_count = 0;

    /* Move head */
    int nx = snake_x[0] + dir_x;
    int ny = snake_y[0] + dir_y;
    if (nx < 0) nx = GRID_W - 1; else if (nx >= GRID_W) nx = 0;
    if (ny < 0) ny = GRID_H - 1; else if (ny >= GRID_H) ny = 0;

    /* Self collision */
    for (int i = 0; i < snake_len; i++) {
        if (snake_x[i] == nx && snake_y[i] == ny) {
            game_over = 1; return;
        }
    }

    /* Shift body */
    for (int i = snake_len; i > 0; i--) {
        snake_x[i] = snake_x[i - 1]; snake_y[i] = snake_y[i - 1];
    }
    snake_x[0] = nx; snake_y[0] = ny;

    /* Eat */
    if (nx == food_x && ny == food_y) {
        snake_len++;
        score += 10;
        if (speed_ms > 30) speed_ms -= 5;
        place_food();
    }

    /* Clear grid area */
    for (int y = 0; y < GRID_H; y++) {
        vga_goto(1, y + 3);
        for (int x = 0; x < GRID_W; x++) vga_putc(' ', VGA_BLACK);
    }

    /* Draw food */
    vga_goto(food_x + 1, food_y + 3);
    vga_putc('@', VGA_RED);

    /* Draw snake */
    vga_goto(snake_x[0] + 1, snake_y[0] + 3);
    vga_putc('O', VGA_YELLOW);
    for (int i = 1; i < snake_len; i++) {
        vga_goto(snake_x[i] + 1, snake_y[i] + 3);
        vga_putc('o', VGA_GREEN);
    }

    /* HUD */
    vga_goto(0, 0);
    vga_puts("SNAKE  Score:", VGA_CYAN);
    char buf[5];
    int s = score;
    for (int i = 3; i >= 0; i--) { buf[i] = '0' + s % 10; s /= 10; }
    buf[4] = 0;
    vga_puts(buf, VGA_YELLOW);
    vga_puts("  ", VGA_BLACK);

    if (game_over) {
        vga_goto(GRID_W/2 - 4, GRID_H/2 + 3);
        vga_puts("GAME OVER", VGA_RED);
    }
}

static void input(char c) {
    if (c == 'q' || c == 'Q') { game_over = 1; initialized = 0; return; }
    int ndx = dir_x, ndy = dir_y;
    switch (c) {
        case 'w': case 'W': ndx =  0; ndy = -1; break;
        case 's': case 'S': ndx =  0; ndy =  1; break;
        case 'a': case 'A': ndx = -1; ndy =  0; break;
        case 'd': case 'D': ndx =  1; ndy =  0; break;
    }
    if (ndx != -dir_x || ndy != -dir_y) { dir_x = ndx; dir_y = ndy; }
}

static int finish(void) { return !initialized; }

const program_t prog_snake = {
    "Snake", "Snake Game — eat the red food!",
    init, update, input, NULL, finish
};
