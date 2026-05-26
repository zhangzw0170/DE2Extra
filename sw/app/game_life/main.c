/*
 * main.c — Conway's Game of Life for DE2Extra
 *
 * 40×20 grid, B3/S23 rules, double-buffered, ANSI terminal rendering.
 * Controls: SPACE=step, P=pause/resume, G=glider, U=gun, R=random, C=clear, Q=quit
 *
 * Dual-mode: LOCAL_BUILD (native GCC, stdin/stdout)
 *            NEORV32 (bare-metal UART)
 */

#include <stdint.h>

#ifdef LOCAL_BUILD
  #include <stdio.h>
  #include <stdlib.h>
  #include <string.h>
  #include <time.h>
  #ifdef _WIN32
    #include <windows.h>
    #include <conio.h>
    #include <io.h>
    static int kbhit_pipe(void) {
        if (_isatty(_fileno(stdin))) return _kbhit();
        HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
        DWORD avail = 0;
        return PeekNamedPipe(h, NULL, 0, NULL, &avail, NULL) && avail > 0;
    }
    static int getch_pipe(void) {
        if (_isatty(_fileno(stdin))) return _getch();
        char c; DWORD n;
        if (ReadFile(GetStdHandle(STD_INPUT_HANDLE), &c, 1, &n, NULL) && n == 1)
            return (unsigned char)c;
        return -1;
    }
    #define _kbhit() kbhit_pipe()
    #define _getch() getch_pipe()
  #else
    #include <conio.h>
  #endif
#else
  #include <neorv32.h>
  #define BAUD_RATE 115200
  #define _kbhit() neorv32_uart0_char_received()
  #define _getch() ((char)neorv32_uart0_getc())
#endif

/* ── Constants ─────────────────────────────────────────────────── */

#define GRID_W  40
#define GRID_H  20
#define GRID_SIZE (GRID_W * GRID_H)

/* ── I/O ───────────────────────────────────────────────────────── */

#ifdef LOCAL_BUILD
  static void io_putc(char c)     { putchar(c); }
  static void io_puts(const char *s) { printf("%s", s); }
  static void io_flush(void)      { fflush(stdout); }
#else
  static void io_putc(char c)     { neorv32_uart0_putc(c); }
  static void io_puts(const char *s) { neorv32_uart0_puts(s); }
  static void io_flush(void)      { }
#endif

/* ── ANSI helpers ──────────────────────────────────────────────── */

static void cursor_home(void) { io_puts("\033[H"); }
static void cursor_goto(int r, int c) {
    io_puts("\033[");
    io_putc('0' + r / 10); io_putc('0' + r % 10);
    io_putc(';');
    io_putc('0' + c / 10); io_putc('0' + c % 10);
    io_putc('H');
}
static void cls(void) { io_puts("\033[2J\033[H\033[?25l"); }

/* ── Random ────────────────────────────────────────────────────── */

static unsigned rng = 0xDEADBEEF;
static void rng_init(void) {
#ifdef LOCAL_BUILD
    rng = (unsigned)time(NULL) ^ 0x12345678;
#endif
}
static int rng_rand(void) {
    rng = rng * 1103515245u + 12345u;
    return (int)(rng >> 16);
}

/* ── Delay (busy-wait) ─────────────────────────────────────────── */

#ifdef LOCAL_BUILD
static void delay_ms(int ms) {
    volatile unsigned long long i;
    for (i = 0; i < (unsigned long long)ms * 10000ull; i++);
}
#else
static void delay_ms(int ms) {
    volatile int i;
    for (i = 0; i < ms * 5000; i++) __asm__ volatile("nop");
}
#endif

/* ── Input ─────────────────────────────────────────────────────── */

static char input_char(void) {
    if (_kbhit()) return (char)_getch();
    return 0;
}

/* ── Grid ──────────────────────────────────────────────────────── */

typedef unsigned char cell_t;  /* 0=dead, 1=alive */
static cell_t cur[GRID_H][GRID_W];
static cell_t nxt[GRID_H][GRID_W];
static int generation;
static int paused;

static void grid_clear(void) {
    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++)
            cur[y][x] = 0;
    generation = 0;
}

static void grid_random(void) {
    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++)
            cur[y][x] = (rng_rand() & 0x7FFF) < 8192;  /* ~25% density */
    generation = 0;
}

/* Place a pattern at (ox, oy) */
static void place_pattern(int ox, int oy, const char *pat, int pw, int ph) {
    for (int y = 0; y < ph; y++) {
        for (int x = 0; x < pw; x++) {
            if (pat[y * pw + x] == 'O') {
                int gx = (ox + x) % GRID_W;
                int gy = (oy + y) % GRID_H;
                cur[gy][gx] = 1;
            }
        }
    }
}

/* Glider (3x3, moves SE) */
static const char glider_pat[] =
    ".O."
    "..O"
    "OOO";

/* Gosper glider gun (36x9) */
static const char gun_pat[] =
    "........................O..........."
    "......................O.O..........."
    "............OO......OO............OO"
    "...........O...O....OO............OO"
    "OO........O.....O...OO.............."
    "OO........O...O.OO....O.O..........."
    "..........O.....O.......O..........."
    "...........O...O...................."
    "............OO......................";

static void grid_glider(void) {
    grid_clear();
    place_pattern(GRID_W/2 - 1, GRID_H/2 - 1, glider_pat, 3, 3);
}

static void grid_gun(void) {
    grid_clear();
    place_pattern(2, 4, gun_pat, 36, 9);
}

/* ── B3/S23 Rules ──────────────────────────────────────────────── */

static int count_neighbors(int x, int y) {
    int count = 0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            int nx = (x + dx + GRID_W) % GRID_W;   /* toroidal wrap */
            int ny = (y + dy + GRID_H) % GRID_H;
            count += cur[ny][nx];
        }
    }
    return count;
}

static void step_generation(void) {
    for (int y = 0; y < GRID_H; y++) {
        for (int x = 0; x < GRID_W; x++) {
            int n = count_neighbors(x, y);
            if (cur[y][x])
                nxt[y][x] = (n == 2 || n == 3) ? 1 : 0;   /* survives */
            else
                nxt[y][x] = (n == 3) ? 1 : 0;              /* born */
        }
    }
    /* Swap buffers */
    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++)
            cur[y][x] = nxt[y][x];
    generation++;
}

/* ── Rendering ─────────────────────────────────────────────────── */

static void draw_border(void) {
    /* Top */
    cursor_goto(3, 9);
    io_putc('+');
    for (int x = 0; x < GRID_W; x++) io_putc('-');
    io_putc('+');
    /* Sides */
    for (int y = 0; y < GRID_H; y++) {
        cursor_goto(4 + y, 9);
        io_putc('|');
        cursor_goto(4 + y, 10 + GRID_W);
        io_putc('|');
    }
    /* Bottom */
    cursor_goto(4 + GRID_H, 9);
    io_putc('+');
    for (int x = 0; x < GRID_W; x++) io_putc('-');
    io_putc('+');
}

static void draw_grid(void) {
    for (int y = 0; y < GRID_H; y++) {
        cursor_goto(4 + y, 10);
        for (int x = 0; x < GRID_W; x++) {
            io_putc(cur[y][x] ? '\xDB' : ' ');  /* █ or space */
        }
    }
}

static void draw_hud(void) {
    cursor_goto(1, 10);
    io_puts("Conway's Game of Life  Gen: ");
    /* Print generation number */
    int g = generation;
    char dbuf[8];
    for (int i = 5; i >= 0; i--) { dbuf[i] = '0' + g % 10; g /= 10; }
    dbuf[6] = '\0';
    io_puts(dbuf);

    /* Count alive cells */
    int alive = 0;
    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++)
            alive += cur[y][x];
    cursor_goto(2, 10);
    io_puts("Alive: ");
    int a = alive;
    char abuf[8];
    for (int i = 3; i >= 0; i--) { abuf[i] = '0' + a % 10; a /= 10; }
    abuf[4] = '\0';
    io_puts(abuf);

    io_puts(paused ? "  [PAUSED]" : "  [RUNNING]");
    io_puts("  G=Gun U=Glider R=Random C=Clear Q=Quit");
}

/* ── Main ──────────────────────────────────────────────────────── */

#ifndef LOCAL_BUILD
int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD_RATE, 0);
    rng_init();
#else
int main(void) {
    rng_init();
#endif

    cls();
    grid_glider();
    paused = 0;

    int frame_delay = 150;  /* ms between generations */

    while (1) {
        char c = input_char();
        switch (c) {
            case ' ': step_generation(); break;
            case 'p': case 'P': paused = !paused; break;
            case 'g': case 'G':
                paused = 1;
                grid_glider();
                break;
            case 'u': case 'U':
            case 'n': case 'N':
                paused = 1;
                grid_gun();
                break;
            case 'r': case 'R':
                paused = 1;
                grid_random();
                break;
            case 'c': case 'C':
                paused = 1;
                grid_clear();
                break;
            case 'q': case 'Q': goto quit;
            case '+': case '=':
                if (frame_delay > 20) frame_delay -= 10;
                break;
            case '-': case '_':
                if (frame_delay < 500) frame_delay += 10;
                break;
        }

        if (!paused) step_generation();

        draw_border();
        draw_grid();
        draw_hud();
        io_flush();

        delay_ms(paused ? 50 : frame_delay);
    }

quit:
    cursor_goto(4 + GRID_H + 2, 9);
    io_puts("                                                        ");
    io_puts("\033[?25h");  /* show cursor */
    io_flush();
    return 0;
}
