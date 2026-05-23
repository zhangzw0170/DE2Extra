/* main.c — DE2Extra Unified Shell
 *
 * 程序调度框架: 根据输入切换活跃程序
 *   - UART 键盘: 直接输入到当前程序
 *   - IR 遥控器: NEC 命令映射到程序切换
 *
 * 子程序 (各自一个 C 文件):
 *   crypto.c   — 密码学终端
 *   snake.c    — 贪吃蛇
 *   life.c     — 康威生命游戏
 *   dashboard.c — 系统仪表盘
 *   info.c     — 系统信息
 */

#include <stdint.h>
#include "vga_hal.h"

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
    #define uart_kbhit() kbhit_pipe()
    #define uart_getc()  getch_pipe()
  #else
    #include <conio.h>
    #define uart_kbhit() _kbhit()
    #define uart_getc()  _getch()
  #endif
  #define uart_putc(c)  putchar(c)
  #define uart_puts(s)  printf("%s", (s))
  static void uart_init(void) {}
#else
  #include <neorv32.h>
  #define BAUD_RATE 115200
  #define uart_kbhit() neorv32_uart0_char_received()
  #define uart_getc()  ((char)neorv32_uart0_getc())
  #define uart_putc(c)  neorv32_uart0_putc(c)
  #define uart_puts(s)  neorv32_uart0_puts(s)
  static void uart_init(void) {
      neorv32_uart0_setup(BAUD_RATE, 0);
  }
#endif

/* ── Program IDs ────────────────────────────────────────────────── */

typedef enum {
    PROG_SHELL = 0,
    PROG_HELLO,
    PROG_MEMTEST,
    PROG_CRYPTO,
    PROG_SNAKE,
    PROG_LIFE,
    PROG_DASHBOARD,
    PROG_INFO,
    PROG_EXP1,
    PROG_EXP4,
    PROG_EXP5,
    PROG_EXP12,
    PROG_MONITOR,
    PROG_COUNT
} prog_id_t;

/* ── Program Interface ──────────────────────────────────────────── */

/* ── Forward declarations ──────────────────────────────────────── */

extern const program_t prog_hello;
extern const program_t prog_memtest;
extern const program_t prog_crypto;
extern const program_t prog_snake;
extern const program_t prog_life;
extern const program_t prog_dashboard;
extern const program_t prog_info;
extern const program_t prog_exp1;
extern const program_t prog_exp4;
extern const program_t prog_exp5;
extern const program_t prog_exp12;
extern const program_t prog_monitor;

/* Dummy strcmp for NEORV32 target (no libc) */
#ifndef LOCAL_BUILD
static int strcmp(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return (unsigned char)*a - (unsigned char)*b;
}
#endif

/* Default empty callbacks — programs that don't implement a callback use these */

static void stub_init(void) {}
static void stub_update(void) {}
static void stub_input(char c) { (void)c; }
static void stub_ir_input(uint8_t cmd) { (void)cmd; }
static int  stub_finish(void) { return 0; }

/* ── Program Registry ───────────────────────────────────────────── */

static const program_t *programs[PROG_COUNT] = {
    [PROG_SHELL]     = NULL,   /* shell is built-in */
    [PROG_HELLO]     = &prog_hello,
    [PROG_MEMTEST]   = &prog_memtest,
    [PROG_CRYPTO]    = &prog_crypto,
    [PROG_SNAKE]     = &prog_snake,
    [PROG_LIFE]      = &prog_life,
    [PROG_DASHBOARD] = &prog_dashboard,
    [PROG_INFO]      = &prog_info,
    [PROG_EXP1]      = &prog_exp1,
    [PROG_EXP4]      = &prog_exp4,
    [PROG_EXP5]      = &prog_exp5,
    [PROG_EXP12]     = &prog_exp12,
    [PROG_MONITOR]   = &prog_monitor,
};

static prog_id_t active_prog = PROG_SHELL;
static prog_id_t ir_prog_map[16];   /* IR command → program mapping */

/* ── Shell (built-in) ───────────────────────────────────────────── */

static void shell_init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("DE2Extra Shell v0.1\n", VGA_CYAN);
    vga_puts("Type 'help' for commands.\n", VGA_GRAY);
}

static void shell_update(void) {
    /* Shell is stateless — render happens in input handler */
}

static void shell_input(char c) {
    /* Shell command dispatch */
    static char line[64];
    static int  line_pos = 0;

    if (c == '\r' || c == '\n') {
        line[line_pos] = '\0';
        vga_putc('\n', VGA_WHITE);

        /* Parse command */
        if (line_pos == 0) {
            /* empty line — show prompt again */
        } else if (strcmp(line, "help") == 0) {
            vga_puts("Commands: hello, memtest, crypto, snake, life, dash, info, exp1, exp4, exp5, exp12, cls, quit\n",
                     VGA_GREEN);
        } else if (strcmp(line, "hello") == 0) {
            active_prog = PROG_HELLO;
            if (programs[PROG_HELLO]->init)
                programs[PROG_HELLO]->init();
        } else if (strcmp(line, "memtest") == 0) {
            active_prog = PROG_MEMTEST;
            if (programs[PROG_MEMTEST]->init)
                programs[PROG_MEMTEST]->init();
        } else if (strcmp(line, "crypto") == 0) {
            active_prog = PROG_CRYPTO;
            if (programs[PROG_CRYPTO]->init)
                programs[PROG_CRYPTO]->init();
        } else if (strcmp(line, "snake") == 0) {
            active_prog = PROG_SNAKE;
            if (programs[PROG_SNAKE]->init)
                programs[PROG_SNAKE]->init();
        } else if (strcmp(line, "life") == 0) {
            active_prog = PROG_LIFE;
            if (programs[PROG_LIFE]->init)
                programs[PROG_LIFE]->init();
        } else if (strcmp(line, "dash") == 0) {
            active_prog = PROG_DASHBOARD;
            if (programs[PROG_DASHBOARD]->init)
                programs[PROG_DASHBOARD]->init();
        } else if (strcmp(line, "info") == 0) {
            active_prog = PROG_INFO;
            if (programs[PROG_INFO]->init)
                programs[PROG_INFO]->init();
        } else if (strcmp(line, "exp1") == 0) {
            active_prog = PROG_EXP1;
            if (programs[PROG_EXP1]->init) programs[PROG_EXP1]->init();
        } else if (strcmp(line, "exp4") == 0) {
            active_prog = PROG_EXP4;
            if (programs[PROG_EXP4]->init) programs[PROG_EXP4]->init();
        } else if (strcmp(line, "exp5") == 0) {
            active_prog = PROG_EXP5;
            if (programs[PROG_EXP5]->init) programs[PROG_EXP5]->init();
        } else if (strcmp(line, "exp12") == 0) {
            active_prog = PROG_EXP12;
            if (programs[PROG_EXP12]->init) programs[PROG_EXP12]->init();
        } else if (strcmp(line, "monitor") == 0 || strcmp(line, "rv32") == 0) {
            active_prog = PROG_MONITOR;
            if (programs[PROG_MONITOR]->init) programs[PROG_MONITOR]->init();
        } else if (strcmp(line, "cls") == 0) {
            vga_clear();
        } else if (strcmp(line, "quit") == 0 || strcmp(line, "exit") == 0) {
            active_prog = PROG_SHELL;
            shell_init();
        } else {
            vga_puts("? Unknown command. Type 'help'\n", VGA_RED);
        }

        line_pos = 0;
        vga_puts("0000> ", VGA_GREEN);
    } else if (c == '\b' || c == 0x7F) {
        if (line_pos > 0) {
            line_pos--;
            vga_putc('\b', VGA_WHITE);
        }
    } else if (c >= ' ' && c < 0x7F && line_pos < (int)sizeof(line) - 1) {
        line[line_pos++] = c;
        vga_putc(c, VGA_WHITE);
    }
}

static int shell_finish(void) { return 0; }

/* ── Status Bar ─────────────────────────────────────────────────── */

static void draw_status_bar(void) {
    vga_goto(0, VGA_ROWS - 1);  /* last row */
    vga_puts(" DE2Extra | Ch:", VGA_CYAN);
    vga_putc('1' + active_prog, VGA_YELLOW);
    if (active_prog < PROG_COUNT && programs[active_prog]) {
        vga_putc(' ', VGA_WHITE);
        vga_puts(programs[active_prog]->name, VGA_GREEN);
    } else {
        vga_puts(" Shell", VGA_GREEN);
    }
    /* Pad to end of line */
    for (int i = vga_col(); i < VGA_COLS; i++)
        vga_putc(' ', VGA_BLACK);
}

/* ── IR Command Handler ─────────────────────────────────────────── */

static void handle_ir(uint8_t cmd) {
    /* Forward IR input to active program first */
    const program_t *prog = programs[active_prog];
    if (prog && prog->ir_input) {
        prog->ir_input(cmd);
        return;
    }

    /* Global IR commands: program switching */
    prog_id_t new_prog = PROG_SHELL;
    switch (cmd) {
        case 0x45: new_prog = PROG_HELLO;     break;  /* CH1 */
        case 0x46: new_prog = PROG_MEMTEST;   break;  /* CH2 */
        case 0x47: new_prog = PROG_CRYPTO;    break;  /* CH3 */
        case 0x44: new_prog = PROG_SNAKE;     break;  /* CH4 */
        case 0x43: new_prog = PROG_LIFE;      break;  /* CH5 */
        case 0x40: new_prog = PROG_DASHBOARD; break;  /* CH6 */
        case 0x07: new_prog = PROG_INFO;      break;  /* CH7 */
        case 0x16: if (active_prog > 0) active_prog--; return;  /* CH- */
        case 0x1A: if (active_prog < PROG_COUNT-1) active_prog++; return; /* CH+ */
        default:   return;  /* unknown key */
    }

    active_prog = new_prog;
    vga_clear();
    if (programs[active_prog] && programs[active_prog]->init)
        programs[active_prog]->init();
}

/* ── Main ──────────────────────────────────────────────────────── */

#ifndef LOCAL_BUILD
int main(void) {
    neorv32_rte_setup();
    uart_init();
#else
int main(void) {
#endif
    vga_init();
    shell_init();
    draw_status_bar();

    while (1) {
        /* Process UART input */
        while (uart_kbhit()) {
            char c = (char)uart_getc();
            if (c == 27) {  /* ESC — check for IR or arrow */
                /* For now, pass through to active program */
            }

            if (active_prog == PROG_SHELL) {
                shell_input(c);
            } else {
                const program_t *prog = programs[active_prog];
                if (prog && prog->input)
                    prog->input(c);
            }
        }

        /* Run active program update */
        const program_t *prog = programs[active_prog];
        if (prog && prog->update) {
            prog->update();
            /* Check for program exit */
            if (prog->finish && prog->finish()) {
                active_prog = PROG_SHELL;
                prog = NULL;
            }
        }
        if (active_prog == PROG_SHELL) {
            shell_update();
        }

        /* Redraw status bar */
        draw_status_bar();

        /* Small delay to limit CPU usage */
#ifdef LOCAL_BUILD
        volatile int i; for (i = 0; i < 50000; i++) {}
#else
        volatile int i; for (i = 0; i < 10000; i++) {}
#endif
    }

    return 0;
}
