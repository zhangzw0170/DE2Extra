/*
 * main.c — Snake Game for DE2Extra
 *
 * 40×20 游戏区域, ANSI escape codes 终端渲染.
 * WASD 或方向键控制, Q 退出.
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
        if (_isatty(_fileno(stdin)))
            return _kbhit();
        HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
        DWORD avail = 0;
        return PeekNamedPipe(h, NULL, 0, NULL, &avail, NULL) && avail > 0;
    }
    static int getch_pipe(void) {
        if (_isatty(_fileno(stdin)))
            return _getch();
        char c;
        DWORD n;
        if (ReadFile(GetStdHandle(STD_INPUT_HANDLE), &c, 1, &n, NULL) && n == 1)
            return (unsigned char)c;
        return -1;
    }
    #define _kbhit() kbhit_pipe()
    #define _getch() getch_pipe()
  #else
    #include <conio.h>
  #endif
  #define BAUD_RATE 115200
#else
  #include <neorv32.h>
  #define BAUD_RATE 115200
  #define _kbhit() neorv32_uart0_char_received()
  #define _getch() ((char)neorv32_uart0_getc())
#endif

/* ── Game Constants ────────────────────────────────────────────── */

#define GRID_W  40
#define GRID_H  20
#define MAX_SNAKE (GRID_W * GRID_H)

/* Use int16_t to fit in limited DMEM */
typedef int16_t coord_t;

/* ── I/O Abstraction ──────────────────────────────────────────── */

#ifdef LOCAL_BUILD
  static void io_putc(char c)     { putchar(c); }
  static void io_puts(const char *s) { printf("%s", s); }
  static void io_flush(void)      { fflush(stdout); }
#else
  static void io_putc(char c)     { neorv32_uart0_putc(c); }
  static void io_puts(const char *s) { neorv32_uart0_puts(s); }
  static void io_flush(void)      { }
#endif

/* ── Cursor Control ────────────────────────────────────────────── */

static void cursor_home(void) {
    io_puts("\033[H");  /* ANSI: cursor to top-left */
}

static void cursor_goto(int row, int col) {
    /* ANSI: cursor to (row, col), 1-based */
    io_puts("\033[");
    io_putc('0' + row / 10);
    io_putc('0' + row % 10);
    io_putc(';');
    io_putc('0' + col / 10);
    io_putc('0' + col % 10);
    io_putc('H');
}

static void clear_screen(void) {
    io_puts("\033[2J\033[H");
}

static void hide_cursor(void) {
    io_puts("\033[?25l");
}

static void show_cursor(void) {
    io_puts("\033[?25h");
}

/* ── Delay ─────────────────────────────────────────────────────── */

#ifdef LOCAL_BUILD
  static void delay_ms(int ms) {
      /* busy-wait approximation */
      volatile unsigned long long i;
      for (i = 0; i < (unsigned long long)ms * 10000ull; i++) {
          /* nop */
      }
  }
#else
  static void delay_ms(int ms) {
      /* NEORV32: use busy-wait, ~50MHz */
      volatile int i;
      for (i = 0; i < ms * 5000; i++) {
          __asm__ volatile ("nop");
      }
  }
#endif

/* ── Random ────────────────────────────────────────────────────── */

static unsigned int rng_state = 0xDEADBEEF;

static void rng_init(void) {
#ifdef LOCAL_BUILD
    rng_state = (unsigned int)time(NULL) ^ 0x12345678;
#else
    /* Use a counter that wraps — good enough for food placement */
    rng_state = 0x12345678;
#endif
}

static int rng_next(void) {
    /* LCG: x_n = 1103515245 * x_{n-1} + 12345 */
    rng_state = rng_state * 1103515245u + 12345u;
    return (int)(rng_state >> 16);
}

static int rng_range(int max) {
    return (rng_next() & 0x7FFFFFFF) % max;
}

/* ── Non-blocking input ────────────────────────────────────────── */

static char input_char(void) {
    if (_kbhit()) {
        return _getch();
    }
    return 0;
}

/* ── Snake Data ────────────────────────────────────────────────── */

static coord_t snake_x[MAX_SNAKE];
static coord_t snake_y[MAX_SNAKE];
static int snake_len;
static int dir_x, dir_y;    /* direction: -1,0,+1 */
static int food_x, food_y;
static int score;
static int game_over;
static int game_speed_ms;
static int esc_state = 0;  /* 0=none, 1=got ESC */

/* ── Game Logic ────────────────────────────────────────────────── */

static void init_game(void) {
    /* Snake starts in center, moving right */
    snake_len = 3;
    int start_x = GRID_W / 2;
    int start_y = GRID_H / 2;
    for (int i = 0; i < snake_len; i++) {
        snake_x[i] = start_x - i;
        snake_y[i] = start_y;
    }
    dir_x = 1;
    dir_y = 0;
    score = 0;
    game_over = 0;
    game_speed_ms = 120;
}

static int food_on_snake(void) {
    for (int i = 0; i < snake_len; i++) {
        if (snake_x[i] == food_x && snake_y[i] == food_y)
            return 1;
    }
    return 0;
}

static void place_food(void) {
    int attempts = 0;
    do {
        food_x = rng_range(GRID_W);
        food_y = rng_range(GRID_H);
        attempts++;
    } while (attempts < 100 && food_on_snake());
}

static void move_snake(int new_dir_x, int new_dir_y) {
    /* Prevent 180-degree turn */
    if (new_dir_x != -dir_x || new_dir_y != -dir_y) {
        dir_x = new_dir_x;
        dir_y = new_dir_y;
    }
}

static int update_snake(void) {
    /* Calculate new head */
    int new_x = snake_x[0] + dir_x;
    int new_y = snake_y[0] + dir_y;

    /* Wall collision — wrap around */
    if (new_x < 0) new_x = GRID_W - 1;
    if (new_x >= GRID_W) new_x = 0;
    if (new_y < 0) new_y = GRID_H - 1;
    if (new_y >= GRID_H) new_y = 0;

    /* Self collision */
    for (int i = 0; i < snake_len; i++) {
        if (snake_x[i] == new_x && snake_y[i] == new_y) {
            return 0; /* hit self */
        }
    }

    /* Move body: shift right */
    for (int i = snake_len; i > 0; i--) {
        snake_x[i] = snake_x[i - 1];
        snake_y[i] = snake_y[i - 1];
    }
    snake_x[0] = new_x;
    snake_y[0] = new_y;

    /* Eat food? */
    if (new_x == food_x && new_y == food_y) {
        snake_len++;
        score += 10;
        if (game_speed_ms > 30) game_speed_ms -= 5;
        place_food();
    }

    return 1;
}

/* ── Rendering ─────────────────────────────────────────────────── */

static void draw_border(void) {
    /* Top border */
    cursor_goto(3, 10);
    io_putc('+');
    for (int x = 0; x < GRID_W; x++) io_putc('-');
    io_putc('+');

    /* Side borders */
    for (int y = 0; y < GRID_H; y++) {
        cursor_goto(4 + y, 10);
        io_putc('|');
        cursor_goto(4 + y, 10 + GRID_W + 1);
        io_putc('|');
    }

    /* Bottom border */
    cursor_goto(4 + GRID_H, 10);
    io_putc('+');
    for (int x = 0; x < GRID_W; x++) io_putc('-');
    io_putc('+');
}

static void draw_grid(void) {
    /* Clear the grid area with spaces */
    for (int y = 0; y < GRID_H; y++) {
        cursor_goto(4 + y, 11);
        for (int x = 0; x < GRID_W; x++) {
            io_putc(' ');
        }
    }
}

static void draw_snake(void) {
    /* Head */
    cursor_goto(4 + snake_y[0], 11 + snake_x[0]);
    io_putc('O');
    /* Body */
    for (int i = 1; i < snake_len; i++) {
        cursor_goto(4 + snake_y[i], 11 + snake_x[i]);
        io_putc('o');
    }
}

static void draw_food(void) {
    cursor_goto(4 + food_y, 11 + food_x);
    io_putc('@');
}

static void draw_hud(void) {
    cursor_goto(1, 10);
    io_puts("=== DE2Extra SNAKE ===  Score: ");
    char buf[8];
    int s = score;
    for (int i = 3; i >= 0; i--) {
        buf[i] = '0' + (s % 10);
        s /= 10;
    }
    buf[4] = '\0';
    io_puts(buf);

    cursor_goto(2, 10);
    io_puts("WASD=Move  Q=Quit  Speed: ");
    int spd = 120 - game_speed_ms;
    io_putc('0' + spd / 10);
    io_putc('0' + spd % 10);
}

static void draw_game_over(void) {
    int cx = 11 + GRID_W / 2 - 5;
    int cy = 4 + GRID_H / 2;
    cursor_goto(cy, cx);
    io_puts("GAME OVER!");
    cursor_goto(cy + 1, cx - 2);
    io_puts("Score: ");
    int s = score;
    io_putc('0' + (s / 1000) % 10);
    io_putc('0' + (s / 100) % 10);
    io_putc('0' + (s / 10) % 10);
    io_putc('0' + s % 10);
    io_flush();
}

/* ── Main ──────────────────────────────────────────────────────── */

#ifndef LOCAL_BUILD
int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD_RATE, 0);
    rng_init();

    clear_screen();
    hide_cursor();

    io_puts("\nDE2Extra Snake Game\n");
    io_puts("Loading...\n");
    delay_ms(500);

    init_game();
    place_food();

    clear_screen();
    draw_border();
    draw_hud();
    draw_food();
    draw_snake();
    io_flush();

    while (!game_over) {
        /* Process input */
        char c = input_char();
        int new_dir_x = dir_x, new_dir_y = dir_y;

        switch (c) {
            case 'w': case 'W': new_dir_x =  0; new_dir_y = -1; break;
            case 's': case 'S': new_dir_x =  0; new_dir_y =  1; break;
            case 'a': case 'A': new_dir_x = -1; new_dir_y =  0; break;
            case 'd': case 'D': new_dir_x =  1; new_dir_y =  0; break;
            case 'q': case 'Q': game_over = 1; continue;
            case 27:
                esc_state = 1; continue;
            default:
                if (esc_state == 1) {
                    esc_state = (c == '[') ? 2 : 0;
                    continue;
                }
                if (esc_state == 2) {
                    esc_state = 0;
                    switch (c) {
                        case 'A': new_dir_x =  0; new_dir_y = -1; break;
                        case 'B': new_dir_x =  0; new_dir_y =  1; break;
                        case 'C': new_dir_x =  1; new_dir_y =  0; break;
                        case 'D': new_dir_x = -1; new_dir_y =  0; break;
                    }
                    break;
                }
                break;
        }
        move_snake(new_dir_x, new_dir_y);

        game_over = !update_snake();

        /* Render */
        draw_grid();
        draw_border();
        draw_food();
        draw_snake();
        draw_hud();
        io_flush();

        delay_ms(game_speed_ms);
    }

    draw_game_over();
    show_cursor();
    cursor_goto(4 + GRID_H + 2, 10);
    io_puts("Press any key to restart...\n");

    /* Wait for key, then restart */
    while (!input_char()) { /* wait */ }
    clear_screen();
    show_cursor();
    return 0;
}
#else
/* LOCAL_BUILD */
int main(void) {
    rng_init();

    clear_screen();
    hide_cursor();

    init_game();
    place_food();

    clear_screen();
    draw_border();
    draw_hud();
    draw_food();
    draw_snake();
    io_flush();

    while (!game_over) {
        char c = input_char();
        int new_dir_x = dir_x, new_dir_y = dir_y;

        switch (c) {
            case 'w': case 'W': new_dir_x =  0; new_dir_y = -1; break;
            case 's': case 'S': new_dir_x =  0; new_dir_y =  1; break;
            case 'a': case 'A': new_dir_x = -1; new_dir_y =  0; break;
            case 'd': case 'D': new_dir_x =  1; new_dir_y =  0; break;
            case 'q': case 'Q': goto quit;
            case 27:
                esc_state = 1; continue;
            default:
                if (esc_state == 1) {
                    esc_state = (c == '[') ? 2 : 0;
                    continue;
                }
                if (esc_state == 2) {
                    esc_state = 0;
                    switch (c) {
                        case 'A': new_dir_x =  0; new_dir_y = -1; break;
                        case 'B': new_dir_x =  0; new_dir_y =  1; break;
                        case 'C': new_dir_x =  1; new_dir_y =  0; break;
                        case 'D': new_dir_x = -1; new_dir_y =  0; break;
                    }
                    break;
                }
                break;
        }
        move_snake(new_dir_x, new_dir_y);

        game_over = !update_snake();

        draw_grid();
        draw_border();
        draw_food();
        draw_snake();
        draw_hud();
        io_flush();

        delay_ms(game_speed_ms);
    }

quit:
    draw_game_over();
    show_cursor();
    cursor_goto(4 + GRID_H + 2, 10);
    io_flush();

    return 0;
}
#endif
