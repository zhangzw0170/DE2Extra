/* snake.c — Snake Game for de2shell
 * Adapted from sw/app/game_snake/main.c
 */
#include "vga_hal.h"
#include <stdint.h>

#define GRID_W 78
#define GRID_H 27
#define MAX_SNAKE (GRID_W * GRID_H)

/* Use int16_t to halve RAM: 2106×2×2 = 8424 bytes (fits DMEM in V2) */
typedef int16_t coord_t;

/* CP437 box-drawing characters */
#define CH_BOX_TL  '\xDA'  /* ┌ */
#define CH_BOX_TR  '\xBF'  /* ┐ */
#define CH_BOX_BL  '\xC0'  /* └ */
#define CH_BOX_BR  '\xD9'  /* ┘ */
#define CH_BOX_HZ  '\xC4'  /* ─ */
#define CH_BOX_VT  '\xB3'  /* │ */

/* ── Difficulty Settings ─────────────────────────────────────── */

#define DIFF_EASY   0
#define DIFF_NORM   1
#define DIFF_HARD   2

struct diff_cfg {
    int base_ms;   /* starting speed (ms per step) */
    int min_ms;    /* speed floor (ms per step) */
    int decel;     /* log curve divisor (higher = gentler) */
};

static const struct diff_cfg diff_table[3] = {
    [DIFF_EASY] = { 160, 70, 12 },
    [DIFF_NORM] = { 120, 50, 10 },
    [DIFF_HARD] = {  90, 35,  8 },
};

static int difficulty;

/* ── Game State ───────────────────────────────────────────────── */

static coord_t snake_x[MAX_SNAKE]
#ifdef DE2SHELL_RTOS
    __attribute__((section(".sdram_bss")))
#endif
    ;
static coord_t snake_y[MAX_SNAKE]
#ifdef DE2SHELL_RTOS
    __attribute__((section(".sdram_bss")))
#endif
    ;
static int snake_len;
static int dir_x, dir_y;
static int food_x, food_y;
static int score;
static int game_over;
static int speed_ms;
static int initialized;
static int frame_count;
static int choosing;  /* difficulty selection state */

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

static void draw_diff_screen(void) {
    vga_clear();
    vga_goto(GRID_W / 2 - 10, 5);
    vga_puts("SNAKE  -  Select Difficulty", VGA_CYAN);
    vga_goto(GRID_W / 2 - 12, 8);
    vga_puts("[1] EASY   - relaxed pace", VGA_GREEN);
    vga_goto(GRID_W / 2 - 12, 10);
    vga_puts("[2] NORMAL - balanced", VGA_YELLOW);
    vga_goto(GRID_W / 2 - 12, 12);
    vga_puts("[3] HARD   - fast & furious", VGA_RED);
    vga_goto(GRID_W / 2 - 8, 15);
    vga_puts("Press 1, 2, or 3", VGA_WHITE);
}

static void start_game(int diff) {
    difficulty = diff;
    const struct diff_cfg *d = &diff_table[diff];
    choosing = 0;

    snake_len = 3;
    int sx = GRID_W / 2, sy = GRID_H / 2;
    for (int i = 0; i < snake_len; i++) {
        snake_x[i] = sx - i; snake_y[i] = sy;
    }
    dir_x = 1; dir_y = 0;
    score = 0;
    game_over = 0;
    speed_ms = d->base_ms;
    frame_count = 0;
    place_food();

    vga_clear();

    const char *labels[] = { "EASY", "NORM", "HARD" };
    vga_goto(1, 0);
    vga_puts("SNAKE(", VGA_CYAN);
    vga_puts(labels[diff], VGA_CYAN);
    vga_puts(") Score: 0", VGA_CYAN);

    /* CP437 box-drawing border — occupies rows 1..GRID_H+2, cols 0..GRID_W+1 */
    vga_goto(0, 1);
    vga_putc(CH_BOX_TL, VGA_WHITE);
    for (int x = 0; x < GRID_W; x++) vga_putc(CH_BOX_HZ, VGA_WHITE);
    vga_putc(CH_BOX_TR, VGA_WHITE);
    for (int y = 0; y < GRID_H; y++) {
        vga_goto(0, y + 2);
        vga_putc(CH_BOX_VT, VGA_WHITE);
        vga_goto(GRID_W + 1, y + 2);
        vga_putc(CH_BOX_VT, VGA_WHITE);
    }
    vga_goto(0, GRID_H + 2);
    vga_putc(CH_BOX_BL, VGA_WHITE);
    for (int x = 0; x < GRID_W; x++) vga_putc(CH_BOX_HZ, VGA_WHITE);
    vga_putc(CH_BOX_BR, VGA_WHITE);

    /* Draw initial food */
    vga_goto(food_x + 1, food_y + 2);
    vga_putc('@', VGA_RED);

    initialized = 1;
}

static void init(void) {
    initialized = 0;
    choosing = 1;
    draw_diff_screen();
}

/* Logarithmic speed: delta = base_ms / (decel * log2(score/10 + 2))
 * Converges toward min_ms, never reaches it. */
static int calc_speed(int score) {
    const struct diff_cfg *d = &diff_table[difficulty];
    int steps = score / 10;
    int delta = d->base_ms / (d->decel * steps + d->decel * 2);
    int spd = d->base_ms - delta;
    return spd < d->min_ms ? d->min_ms : spd;
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

    /* Self collision (exclude tail — it will move away this frame) */
    int check_len = (snake_len > 1) ? snake_len - 1 : 1;
    for (int i = 0; i < check_len; i++) {
        if (snake_x[i] == nx && snake_y[i] == ny) {
            game_over = 1;
            vga_goto(GRID_W / 2 - 4, GRID_H / 2 + 1);
            vga_puts("GAME OVER", VGA_RED);
            vga_goto(GRID_W / 2 - 8, GRID_H / 2 + 3);
            vga_puts("R/Space=retry  Q=quit", VGA_WHITE);
            return;
        }
    }

    /* Save old tail before shift */
    int old_tail_x = snake_x[snake_len - 1];
    int old_tail_y = snake_y[snake_len - 1];

    /* Shift body */
    for (int i = snake_len; i > 0; i--) {
        snake_x[i] = snake_x[i - 1]; snake_y[i] = snake_y[i - 1];
    }
    snake_x[0] = nx; snake_y[0] = ny;

    int ate = (nx == food_x && ny == food_y);
    if (ate && snake_len < MAX_SNAKE) {
        snake_len++;
        score += 10;
        speed_ms = calc_speed(score);
        place_food();
    }

    /* Wait for vblank before drawing to avoid tearing artifacts */
    vga_wait_vblank();

    /* Incremental VGA redraw — no full clear */
    if (!ate) {
        vga_goto(old_tail_x + 1, old_tail_y + 2);
        vga_putc(' ', VGA_BLACK);
    }
    if (snake_len > 1) {
        vga_goto(snake_x[1] + 1, snake_y[1] + 2);
        vga_putc('o', VGA_GREEN);
    }
    vga_goto(snake_x[0] + 1, snake_y[0] + 2);
    vga_putc('O', VGA_YELLOW);
    if (ate) {
        vga_goto(food_x + 1, food_y + 2);
        vga_putc('@', VGA_RED);
    }

    /* HUD */
    const char *labels[] = { "EASY", "NORM", "HARD" };
    vga_goto(1, 0);
    vga_puts("SNAKE(", VGA_CYAN);
    vga_puts(labels[difficulty], VGA_CYAN);
    vga_puts(") Score:", VGA_CYAN);
    {
        char buf[6];
        int s = score;
        int d = 0;
        if (s == 0) { buf[d++] = '0'; }
        else {
            char tmp[6]; int t = 0;
            while (s > 0 && t < 5) { tmp[t++] = '0' + s % 10; s /= 10; }
            while (t > 0) buf[d++] = tmp[--t];
        }
        buf[d] = 0;
        vga_puts(buf, VGA_YELLOW);
    }
    vga_puts("  ", VGA_BLACK);
}

static void input(char c) {
    if (c == 'q' || c == 'Q') { game_over = 1; initialized = 0; choosing = 0; return; }

    /* Difficulty selection screen */
    if (choosing) {
        if (c == '1') start_game(DIFF_EASY);
        else if (c == '2') start_game(DIFF_NORM);
        else if (c == '3') start_game(DIFF_HARD);
        return;
    }

    /* Game over → restart with same difficulty */
    if (game_over) {
        if (c == 'r' || c == 'R' || c == ' ') start_game(difficulty);
        return;
    }

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
