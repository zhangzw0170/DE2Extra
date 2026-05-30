/* snake.c — Snake Game (1P / 2P) for de2shell
 *
 * 1P: WASD or Arrow keys
 * 2P: P1 = WASD, P2 = Arrow keys
 * F10 = quit (no more accidental Q from WASD!)
 */
#include "vga_hal.h"
#include "ps2_decoder.h"
#include <stdint.h>

#define GRID_W     78
#define GRID_H     27
#define MAX_SNAKE  (GRID_W * GRID_H)

typedef int16_t coord_t;

/* CP437 box-drawing characters */
#define CH_TL  '\xDA'
#define CH_TR  '\xBF'
#define CH_BL  '\xC0'
#define CH_BR  '\xD9'
#define CH_HZ  '\xC4'
#define CH_VT  '\xB3'

/* ── Difficulty ──────────────────────────────────────────────── */

#define DIFF_EASY  0
#define DIFF_NORM  1
#define DIFF_HARD  2

struct diff_cfg { int base_ms, min_ms, decel; };

static const struct diff_cfg diff_table[3] = {
    [DIFF_EASY] = { 160, 70, 12 },
    [DIFF_NORM] = { 120, 50, 10 },
    [DIFF_HARD] = {  90, 35,  8 },
};

static int difficulty;

/* ── Snake State ─────────────────────────────────────────────── */

typedef struct {
    coord_t x[MAX_SNAKE];
    coord_t y[MAX_SNAKE];
    int len, dx, dy, score;
} snake_t;

static snake_t p1
#ifdef DE2SHELL_RTOS
    __attribute__((section(".sdram_bss")))
#endif
    ;
static snake_t p2
#ifdef DE2SHELL_RTOS
    __attribute__((section(".sdram_bss")))
#endif
    ;

static int two_player;
static int food_x, food_y;
static int game_over, speed_ms, initialized, frame_count;
static int choosing;   /* 1=mode select, 2=difficulty, 0=playing */
static int winner;     /* 0=none, 1=P1, 2=P2, 3=draw */
static unsigned rng = 0x12345678;

/* ── RNG ─────────────────────────────────────────────────────── */

static int rng_range(int max) {
    rng = rng * 1103515245u + 12345u;
    return ((int)(rng >> 16) & 0x7FFFFFFF) % max;
}

/* ── Helpers ─────────────────────────────────────────────────── */

static int food_on_any(void) {
    for (int i = 0; i < p1.len; i++)
        if (p1.x[i] == food_x && p1.y[i] == food_y) return 1;
    if (two_player)
        for (int i = 0; i < p2.len; i++)
            if (p2.x[i] == food_x && p2.y[i] == food_y) return 1;
    return 0;
}

static void place_food(void) {
    int tries = 0;
    do {
        food_x = rng_range(GRID_W);
        food_y = rng_range(GRID_H);
    } while (++tries < 200 && food_on_any());
}

static void print_int(int val, uint16_t col) {
    char buf[6];
    int d = 0;
    if (val == 0) { buf[d++] = '0'; }
    else {
        char tmp[6]; int t = 0;
        while (val > 0 && t < 5) { tmp[t++] = '0' + val % 10; val /= 10; }
        while (t > 0) buf[d++] = tmp[--t];
    }
    buf[d] = 0;
    vga_puts(buf, col);
}

/* ── Selection Screens ───────────────────────────────────────── */

static void draw_mode_screen(void) {
    vga_clear();
    vga_goto(33, 5);
    vga_puts("SNAKE", VGA_CYAN);
    vga_goto(28, 9);
    vga_puts("[1] Single Player", VGA_GREEN);
    vga_goto(28, 11);
    vga_puts("[2] Two Players", VGA_YELLOW);
    vga_goto(30, 14);
    vga_puts("Press 1 or 2", VGA_WHITE);
    vga_goto(20, 18);
    vga_puts("P1: WASD   P2: Arrows   F10: Quit", VGA_GRAY);
}

static void draw_diff_screen(void) {
    vga_clear();
    vga_goto(25, 5);
    vga_puts(two_player ? "SNAKE 2P - Difficulty" : "SNAKE - Difficulty", VGA_CYAN);
    vga_goto(25, 8);
    vga_puts("[1] EASY   - relaxed pace", VGA_GREEN);
    vga_goto(25, 10);
    vga_puts("[2] NORMAL - balanced", VGA_YELLOW);
    vga_goto(25, 12);
    vga_puts("[3] HARD   - fast & furious", VGA_RED);
    vga_goto(27, 15);
    vga_puts("Press 1, 2, or 3", VGA_WHITE);
}

/* ── Start Game ──────────────────────────────────────────────── */

static void init_snake(snake_t *s, int sx, int sy, int dx) {
    s->len = 3;
    s->dx = dx;
    s->dy = 0;
    s->score = 0;
    for (int i = 0; i < s->len; i++) {
        s->x[i] = sx - i * dx;
        s->y[i] = sy;
    }
}

static void draw_border(void) {
    vga_goto(0, 1);
    vga_putc(CH_TL, VGA_WHITE);
    for (int x = 0; x < GRID_W; x++) vga_putc(CH_HZ, VGA_WHITE);
    vga_putc(CH_TR, VGA_WHITE);
    for (int y = 0; y < GRID_H; y++) {
        vga_goto(0, y + 2);
        vga_putc(CH_VT, VGA_WHITE);
        vga_goto(GRID_W + 1, y + 2);
        vga_putc(CH_VT, VGA_WHITE);
    }
    vga_goto(0, GRID_H + 2);
    vga_putc(CH_BL, VGA_WHITE);
    for (int x = 0; x < GRID_W; x++) vga_putc(CH_HZ, VGA_WHITE);
    vga_putc(CH_BR, VGA_WHITE);
}

static void start_game(int diff) {
    difficulty = diff;
    choosing = 0;
    winner = 0;
    game_over = 0;
    speed_ms = diff_table[diff].base_ms;
    frame_count = 0;

    init_snake(&p1, GRID_W / 4, GRID_H / 2, 1);
    if (two_player)
        init_snake(&p2, GRID_W * 3 / 4, GRID_H / 2, -1);

    place_food();
    vga_clear();

    /* HUD header */
    const char *labels[] = { "EASY", "NORM", "HARD" };
    vga_goto(1, 0);
    vga_puts(two_player ? "2P(" : "SNAKE(", VGA_CYAN);
    vga_puts(labels[diff], VGA_CYAN);
    vga_puts(") ", VGA_CYAN);
    vga_goto(15, 0);
    vga_puts("P1:", VGA_GREEN);
    print_int(0, VGA_YELLOW);
    if (two_player) {
        vga_goto(40, 0);
        vga_puts("P2:", VGA_CYAN);
        print_int(0, VGA_YELLOW);
    }

    draw_border();

    /* Draw initial P1 */
    for (int i = 0; i < p1.len; i++) {
        vga_goto(p1.x[i] + 1, p1.y[i] + 2);
        vga_putc(i ? 'o' : 'O', i ? VGA_GREEN : VGA_YELLOW);
    }
    /* Draw initial P2 */
    if (two_player) {
        for (int i = 0; i < p2.len; i++) {
            vga_goto(p2.x[i] + 1, p2.y[i] + 2);
            vga_putc(i ? '=' : '#', i ? VGA_BLUE : VGA_CYAN);
        }
    }
    /* Draw food */
    vga_goto(food_x + 1, food_y + 2);
    vga_putc('@', VGA_RED);

    initialized = 1;
}

static void init(void) {
    initialized = 0;
    choosing = 1;
    two_player = 0;
    draw_mode_screen();
}

/* ── Speed ───────────────────────────────────────────────────── */

static int calc_speed(void) {
    const struct diff_cfg *d = &diff_table[difficulty];
    int total = p1.score + (two_player ? p2.score : 0);
    int steps = total / 10;
    int delta = d->base_ms / (d->decel * steps + d->decel * 2);
    int spd = d->base_ms - delta;
    return spd < d->min_ms ? d->min_ms : spd;
}

/* ── Collision ───────────────────────────────────────────────── */

static int hits_body(snake_t *s, int nx, int ny) {
    int end = (s->len > 1) ? s->len - 1 : 1;
    for (int i = 0; i < end; i++)
        if (s->x[i] == nx && s->y[i] == ny) return 1;
    return 0;
}

/* ── Update ──────────────────────────────────────────────────── */

static void update(void) {
    if (!initialized || game_over) return;
    if (++frame_count < speed_ms / 10) return;
    frame_count = 0;

    /* 1. Calculate new heads (wrap around) */
    int nx1 = (p1.x[0] + p1.dx + GRID_W) % GRID_W;
    int ny1 = (p1.y[0] + p1.dy + GRID_H) % GRID_H;
    int nx2 = 0, ny2 = 0;
    if (two_player) {
        nx2 = (p2.x[0] + p2.dx + GRID_W) % GRID_W;
        ny2 = (p2.y[0] + p2.dy + GRID_H) % GRID_H;
    }

    /* 2. Collision check */
    int p1_dead = hits_body(&p1, nx1, ny1);
    int p2_dead = 0;
    if (two_player) {
        p2_dead = hits_body(&p2, nx2, ny2);
        if (hits_body(&p2, nx1, ny1)) p1_dead = 1;
        if (hits_body(&p1, nx2, ny2)) p2_dead = 1;
        if (nx1 == nx2 && ny1 == ny2) { p1_dead = 1; p2_dead = 1; }
    }

    if (p1_dead || p2_dead) {
        game_over = 1;
        vga_goto(GRID_W / 2 - 4, GRID_H / 2 + 1);
        if (!two_player) {
            vga_puts("GAME OVER", VGA_RED);
        } else {
            winner = (p1_dead && p2_dead) ? 3 : p1_dead ? 2 : 1;
            if (winner == 1)      vga_puts("P1 WINS!", VGA_GREEN);
            else if (winner == 2) vga_puts("P2 WINS!", VGA_CYAN);
            else                  vga_puts("  DRAW!  ", VGA_YELLOW);
        }
        vga_goto(GRID_W / 2 - 10, GRID_H / 2 + 3);
        vga_puts("R/Space=retry  F10=quit", VGA_WHITE);
        return;
    }

    /* 3. Save old tails */
    int otx1 = p1.x[p1.len - 1], oty1 = p1.y[p1.len - 1];
    int otx2 = 0, oty2 = 0;
    if (two_player) {
        otx2 = p2.x[p2.len - 1]; oty2 = p2.y[p2.len - 1];
    }

    /* 4. Shift bodies */
    for (int i = p1.len; i > 0; i--) {
        p1.x[i] = p1.x[i - 1]; p1.y[i] = p1.y[i - 1];
    }
    p1.x[0] = nx1; p1.y[0] = ny1;
    if (two_player) {
        for (int i = p2.len; i > 0; i--) {
            p2.x[i] = p2.x[i - 1]; p2.y[i] = p2.y[i - 1];
        }
        p2.x[0] = nx2; p2.y[0] = ny2;
    }

    /* 5. Check food */
    int ate1 = (nx1 == food_x && ny1 == food_y);
    int ate2 = two_player && (nx2 == food_x && ny2 == food_y);
    if (ate1 && p1.len < MAX_SNAKE) p1.len++;
    if (ate1) p1.score += 10;
    if (ate2 && p2.len < MAX_SNAKE) p2.len++;
    if (ate2) p2.score += 10;

    /* 6. Draw (vblank to avoid tearing) */
    vga_wait_vblank();

    /* Clear old tails */
    if (!ate1) { vga_goto(otx1 + 1, oty1 + 2); vga_putc(' ', VGA_BLACK); }
    if (two_player && !ate2) { vga_goto(otx2 + 1, oty2 + 2); vga_putc(' ', VGA_BLACK); }

    /* P1 body + head */
    if (p1.len > 1) { vga_goto(p1.x[1] + 1, p1.y[1] + 2); vga_putc('o', VGA_GREEN); }
    vga_goto(p1.x[0] + 1, p1.y[0] + 2); vga_putc('O', VGA_YELLOW);

    /* P2 body + head */
    if (two_player) {
        if (p2.len > 1) { vga_goto(p2.x[1] + 1, p2.y[1] + 2); vga_putc('=', VGA_BLUE); }
        vga_goto(p2.x[0] + 1, p2.y[0] + 2); vga_putc('#', VGA_CYAN);
    }

    /* New food if eaten */
    if (ate1 || ate2) {
        speed_ms = calc_speed();
        place_food();
        vga_goto(food_x + 1, food_y + 2); vga_putc('@', VGA_RED);
    }

    /* Update score HUD */
    vga_goto(18, 0);
    print_int(p1.score, VGA_YELLOW);
    if (two_player) {
        vga_goto(43, 0);
        print_int(p2.score, VGA_YELLOW);
    }
    vga_puts("  ", VGA_BLACK);
}

/* ── Input ───────────────────────────────────────────────────── */

static void input(char c) {
    uint8_t k = (uint8_t)c;

    /* F10 = quit */
    if (k == PS2_VK_F10) { game_over = 1; initialized = 0; choosing = 0; return; }

    /* Mode selection */
    if (choosing == 1) {
        if (k == '1') { two_player = 0; choosing = 2; draw_diff_screen(); }
        else if (k == '2') { two_player = 1; choosing = 2; draw_diff_screen(); }
        return;
    }

    /* Difficulty selection */
    if (choosing == 2) {
        if (k == '1') start_game(DIFF_EASY);
        else if (k == '2') start_game(DIFF_NORM);
        else if (k == '3') start_game(DIFF_HARD);
        return;
    }

    /* Game over → restart */
    if (game_over) {
        if (k == 'r' || k == 'R' || k == ' ') start_game(difficulty);
        return;
    }

    /* P1: WASD */
    {
        int ndx = p1.dx, ndy = p1.dy;
        switch (k) {
            case 'w': case 'W': ndx =  0; ndy = -1; break;
            case 's': case 'S': ndx =  0; ndy =  1; break;
            case 'a': case 'A': ndx = -1; ndy =  0; break;
            case 'd': case 'D': ndx =  1; ndy =  0; break;
        }
        if (ndx != -p1.dx || ndy != -p1.dy) { p1.dx = ndx; p1.dy = ndy; }
    }

    if (!two_player) {
        /* 1P: arrows also control P1 */
        int ndx = p1.dx, ndy = p1.dy;
        switch (k) {
            case PS2_VK_UP:    ndx =  0; ndy = -1; break;
            case PS2_VK_DOWN:  ndx =  0; ndy =  1; break;
            case PS2_VK_LEFT:  ndx = -1; ndy =  0; break;
            case PS2_VK_RIGHT: ndx =  1; ndy =  0; break;
        }
        if (ndx != -p1.dx || ndy != -p1.dy) { p1.dx = ndx; p1.dy = ndy; }
    } else {
        /* 2P: arrows control P2 */
        int ndx = p2.dx, ndy = p2.dy;
        switch (k) {
            case PS2_VK_UP:    ndx =  0; ndy = -1; break;
            case PS2_VK_DOWN:  ndx =  0; ndy =  1; break;
            case PS2_VK_LEFT:  ndx = -1; ndy =  0; break;
            case PS2_VK_RIGHT: ndx =  1; ndy =  0; break;
        }
        if (ndx != -p2.dx || ndy != -p2.dy) { p2.dx = ndx; p2.dy = ndy; }
    }
}

static int finish(void) { return (!initialized) && (!choosing); }

const program_t prog_snake = {
    "Snake", "Snake (1P/2P) — eat the food!",
    init, update, input, NULL, finish
};
