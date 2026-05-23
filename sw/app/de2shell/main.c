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
#include "gpio_hal.h"

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
    PROG_PS2,
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

static void shell_init(void);

extern const program_t prog_hello;
extern const program_t prog_memtest;
extern const program_t prog_crypto;
extern const program_t prog_ps2;
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
    [PROG_PS2]       = &prog_ps2,
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
static int status_dirty = 1;
static uint8_t last_uart_char = 0;
static uint8_t prev_key_bits = 0;
static uint32_t shell_tick = 0;

#define KEY1_MASK (1u << 0)
#define KEY2_MASK (1u << 1)
#define KEY3_MASK (1u << 2)

static void shell_prompt(void) {
    vga_puts("0000> ", VGA_GREEN);
}

static int valid_prog_id(uint32_t prog_id) {
    return prog_id < PROG_COUNT;
}

static prog_id_t shell_selected_prog(uint32_t gpio_in) {
    uint32_t sel = gpio_in & 0x0fu;
    if (!valid_prog_id(sel)) {
        return PROG_SHELL;
    }
    return (prog_id_t)sel;
}

static void board_status_push(uint32_t word) {
    gpio_write_out(word);
}

static void board_status_refresh(void) {
    uint32_t gpio_in = gpio_read_in();
    uint32_t selected = (uint32_t)shell_selected_prog(gpio_in);
    uint32_t key_bits = (gpio_in >> 18) & 0x7u;
    uint32_t out;

    if (active_prog == PROG_MEMTEST) {
        return; /* memtest owns the LCD/LED fail/pass protocol */
    }

    if (active_prog == PROG_SHELL) {
        out = 0x40000000u;
        out |= ((uint32_t)active_prog & 0x0fu) << 24;
        out |= (selected & 0x0fu) << 20;
        out |= (key_bits & 0x07u) << 17;
        out |= ((shell_tick >> 8) & 0x01u) << 16;
        out |= (gpio_in & 0x000000ffu) << 8;
        out |= (uint32_t)last_uart_char;
        board_status_push(out);
    } else {
        out = gpio_read_out();
        out &= 0x00ffffffu;
        out |= 0x40000000u;
        out |= ((uint32_t)active_prog & 0x0fu) << 24;
        board_status_push(out);
    }
}

static void enter_program(prog_id_t prog_id) {
    active_prog = prog_id;
    status_dirty = 1;
    if ((prog_id < PROG_COUNT) && programs[prog_id] && programs[prog_id]->init) {
        programs[prog_id]->init();
    }
}

static void return_to_shell(void) {
    active_prog = PROG_SHELL;
    status_dirty = 1;
    shell_init();
    board_status_refresh();
}

/* ── Shell (built-in) ───────────────────────────────────────────── */

static void shell_init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("DE2Extra Shell v0.1\n", VGA_CYAN);
    vga_puts("Type 'help' for commands.\n\n", VGA_GRAY);
    shell_prompt();
}

static void shell_update(void) {
    /* Shell is stateless — render happens in input handler */
}

static void shell_input(char c) {
    /* Shell command dispatch */
    static char line[64];
    static int  line_pos = 0;

    if (c == '\r' || c == '\n') {
        int prompt_already_printed = 0;

        line[line_pos] = '\0';
        vga_putc('\n', VGA_WHITE);

        /* Parse command */
        if (line_pos == 0) {
            /* empty line — show prompt again */
        } else if (strcmp(line, "help") == 0) {
            vga_puts("Commands: hello, memtest, sdram, crypto, ps2, snake, life, dash, info, monitor, exp1, exp4, exp5, exp12, cls, quit\n",
                     VGA_GREEN);
        } else if (strcmp(line, "hello") == 0) {
            enter_program(PROG_HELLO);
        } else if (strcmp(line, "memtest") == 0 || strcmp(line, "sdram") == 0 ||
                   strcmp(line, "sdram_test") == 0) {
            enter_program(PROG_MEMTEST);
        } else if (strcmp(line, "crypto") == 0) {
            enter_program(PROG_CRYPTO);
        } else if (strcmp(line, "ps2") == 0 || strcmp(line, "kbd") == 0) {
            enter_program(PROG_PS2);
        } else if (strcmp(line, "snake") == 0) {
            enter_program(PROG_SNAKE);
        } else if (strcmp(line, "life") == 0) {
            enter_program(PROG_LIFE);
        } else if (strcmp(line, "dash") == 0) {
            enter_program(PROG_DASHBOARD);
        } else if (strcmp(line, "info") == 0) {
            enter_program(PROG_INFO);
        } else if (strcmp(line, "exp1") == 0) {
            enter_program(PROG_EXP1);
        } else if (strcmp(line, "exp4") == 0) {
            enter_program(PROG_EXP4);
        } else if (strcmp(line, "exp5") == 0) {
            enter_program(PROG_EXP5);
        } else if (strcmp(line, "exp12") == 0) {
            enter_program(PROG_EXP12);
        } else if (strcmp(line, "monitor") == 0 || strcmp(line, "rv32") == 0) {
            enter_program(PROG_MONITOR);
        } else if (strcmp(line, "cls") == 0) {
            shell_init();
            prompt_already_printed = 1;
        } else if (strcmp(line, "quit") == 0 || strcmp(line, "exit") == 0) {
            return_to_shell();
            prompt_already_printed = 1;
        } else {
            vga_puts("? Unknown command. Type 'help'\n", VGA_RED);
        }

        line_pos = 0;
        if ((active_prog == PROG_SHELL) && !prompt_already_printed) {
            shell_prompt();
        }
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
    static const char hex[] = "0123456789ABCDEF";
    int saved_col;
    int saved_row;

    if (!status_dirty) {
        return;
    }

    saved_col = vga_col();
    saved_row = vga_row();
    vga_goto(0, VGA_ROWS - 1);  /* last row */
    vga_puts(" DE2Extra | Ch:", VGA_CYAN);
    vga_putc(hex[active_prog & 0x0f], VGA_YELLOW);
    if (active_prog < PROG_COUNT && programs[active_prog]) {
        vga_putc(' ', VGA_WHITE);
        vga_puts(programs[active_prog]->name, VGA_GREEN);
    } else {
        vga_puts(" Shell", VGA_GREEN);
    }
    /* Pad to end of line */
    for (int i = vga_col(); i < VGA_COLS; i++)
        vga_putc(' ', VGA_BLACK);
    vga_goto(saved_col, saved_row);
    status_dirty = 0;
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
        case 0x16:
            if (active_prog > 0) {
                new_prog = active_prog - 1;
                break;
            }
            return;  /* CH- */
        case 0x1A:
            if (active_prog < PROG_COUNT - 1) {
                new_prog = active_prog + 1;
                break;
            }
            return; /* CH+ */
        default:   return;  /* unknown key */
    }

    if (new_prog == PROG_SHELL) {
        return_to_shell();
    } else {
        enter_program(new_prog);
    }
}

static void handle_keys(void) {
    uint32_t gpio_in = gpio_read_in();
    uint8_t key_bits = (uint8_t)((gpio_in >> 18) & 0x07u);
    uint8_t pressed = (uint8_t)(key_bits & (uint8_t)(~prev_key_bits));
    prog_id_t quick_prog = shell_selected_prog(gpio_in);
    const program_t *prog = programs[active_prog];

    prev_key_bits = key_bits;

    if (pressed & KEY1_MASK) {
        if (quick_prog == PROG_SHELL) {
            return_to_shell();
        } else {
            enter_program(quick_prog);
        }
    }

    if (pressed & KEY2_MASK) {
        return_to_shell();
    }

    if (pressed & KEY3_MASK) {
        if (active_prog == PROG_SHELL) {
            shell_init();
        } else if (prog && prog->init) {
            prog->init();
            status_dirty = 1;
        }
    }
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
    board_status_refresh();
    draw_status_bar();

    while (1) {
        shell_tick++;
        handle_keys();

        /* Process UART input */
        while (uart_kbhit()) {
            char c = (char)uart_getc();
            last_uart_char = (uint8_t)c;
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
                return_to_shell();
                prog = NULL;
            }
        }
        if (active_prog == PROG_SHELL) {
            shell_update();
        }

        board_status_refresh();

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
