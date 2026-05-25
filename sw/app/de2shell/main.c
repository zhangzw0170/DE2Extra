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
 *   info.c     — 系统信息 + 实时板级状态
 */

#include <stdint.h>
#include "board_status.h"
#include "lcd_hal.h"
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
  #define uart_init() ((void)0)
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

  typedef volatile struct {
      uint32_t data;
      uint32_t status;
  } ir_regs_t;

  #define IR_STATUS_VALID  0x00000001u
  #define IR_STATUS_REPEAT 0x00000002u
  #define IR ((ir_regs_t*)0xF0009000u)
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
    PROG_MONITOR,
    PROG_DEMO,
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
extern const program_t prog_info;
extern const program_t prog_monitor;
extern const program_t prog_demo;

/* Dummy strcmp for NEORV32 target (no libc) */
#ifndef LOCAL_BUILD
static int strcmp(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return (unsigned char)*a - (unsigned char)*b;
}
#endif

/* Default empty callbacks — programs that don't implement a callback use these */

/* ── Program Registry ───────────────────────────────────────────── */

static const program_t *programs[PROG_COUNT] = {
    [PROG_SHELL]     = NULL,   /* shell is built-in */
    [PROG_HELLO]     = &prog_hello,
    [PROG_MEMTEST]   = &prog_memtest,
    [PROG_CRYPTO]    = &prog_crypto,
    [PROG_PS2]       = &prog_ps2,
    [PROG_SNAKE]     = &prog_snake,
    [PROG_LIFE]      = &prog_life,
    [PROG_DASHBOARD] = &prog_info,
    [PROG_INFO]      = &prog_info,
    [PROG_MONITOR]   = &prog_monitor,
    [PROG_DEMO]      = &prog_demo,
};

static prog_id_t active_prog = PROG_SHELL;
static int status_dirty = 1;
static uint8_t last_uart_char = 0;
static uint8_t prev_key_bits = 0;
#ifndef LOCAL_BUILD
static uint8_t prev_ir_toggle = 0;
#endif
uint8_t last_ir_cmd = 0;

#define SHELL_LINE_SIZE 48
#define SHELL_HISTORY_DEPTH 4
static char shell_line[SHELL_LINE_SIZE];
static int shell_line_pos = 0;
static char shell_saved_line[SHELL_LINE_SIZE];
static char shell_history[SHELL_HISTORY_DEPTH][SHELL_LINE_SIZE];
static int shell_history_count = 0;
static int shell_history_nav = -1;
static int shell_esc_state = 0;

#define KEY1_MASK (1u << 0)
#define KEY2_MASK (1u << 1)
#define KEY3_MASK (1u << 2)

/* Exp10 remote profile (table 6-16 indexes the physical keys row-by-row) */
#define IR_BTN_A       0x0Fu
#define IR_BTN_B       0x13u
#define IR_BTN_C       0x10u
#define IR_BTN_POWER   0x12u
#define IR_BTN_1       0x01u
#define IR_BTN_2       0x02u
#define IR_BTN_3       0x03u
#define IR_BTN_CH_UP   0x1Au
#define IR_BTN_4       0x04u
#define IR_BTN_5       0x05u
#define IR_BTN_6       0x06u
#define IR_BTN_CH_DN   0x1Eu
#define IR_BTN_7       0x07u
#define IR_BTN_8       0x08u
#define IR_BTN_9       0x09u
#define IR_BTN_VOL_UP  0x1Bu
#define IR_BTN_MENU    0x11u
#define IR_BTN_0       0x00u
#define IR_BTN_RETURN  0x17u
#define IR_BTN_VOL_DN  0x1Fu
#define IR_BTN_PLAY    0x16u
#define IR_BTN_ADJ_LT  0x14u
#define IR_BTN_ADJ_GT  0x18u
#define IR_BTN_MUTE    0x0Cu

static void shell_prompt(void) {
    vga_puts("0000 > ", VGA_GREEN);
}

static void shell_redraw_line(int old_len) {
    vga_putc('\r', VGA_WHITE);
    shell_prompt();
    for (int i = 0; i < shell_line_pos; i++) {
        vga_putc(shell_line[i], VGA_WHITE);
    }
    for (int i = shell_line_pos; i < old_len; i++) {
        vga_putc(' ', VGA_WHITE);
    }
    vga_putc('\r', VGA_WHITE);
    shell_prompt();
    for (int i = 0; i < shell_line_pos; i++) {
        vga_putc(shell_line[i], VGA_WHITE);
    }
}

static void shell_history_store_current(void) {
    for (int i = 0; i <= shell_line_pos; i++) {
        shell_saved_line[i] = shell_line[i];
    }
}

static void shell_history_load(const char *src) {
    int i = 0;
    while (src[i] && i < SHELL_LINE_SIZE - 1) {
        shell_line[i] = src[i];
        i++;
    }
    shell_line[i] = '\0';
    shell_line_pos = i;
}

static void shell_history_push(void) {
    if (shell_line_pos == 0) {
        return;
    }
    if ((shell_history_count > 0) && (strcmp(shell_history[shell_history_count - 1], shell_line) == 0)) {
        return;
    }
    if (shell_history_count < SHELL_HISTORY_DEPTH) {
        for (int i = 0; i <= shell_line_pos; i++) {
            shell_history[shell_history_count][i] = shell_line[i];
        }
        shell_history_count++;
    } else {
        for (int i = 1; i < SHELL_HISTORY_DEPTH; i++) {
            for (int j = 0; j < SHELL_LINE_SIZE; j++) {
                shell_history[i - 1][j] = shell_history[i][j];
            }
        }
        for (int i = 0; i <= shell_line_pos; i++) {
            shell_history[SHELL_HISTORY_DEPTH - 1][i] = shell_line[i];
        }
    }
}

static void shell_history_prev(void) {
    int old_len = shell_line_pos;
    if (shell_history_count <= 0) {
        return;
    }
    if (shell_history_nav < 0) {
        shell_history_store_current();
        shell_history_nav = shell_history_count - 1;
    } else if (shell_history_nav > 0) {
        shell_history_nav--;
    } else {
        return;
    }
    shell_history_load(shell_history[shell_history_nav]);
    shell_redraw_line(old_len);
}

static void shell_history_next(void) {
    int old_len = shell_line_pos;
    if (shell_history_nav < 0) {
        return;
    }
    if (shell_history_nav < (shell_history_count - 1)) {
        shell_history_nav++;
        shell_history_load(shell_history[shell_history_nav]);
    } else {
        shell_history_nav = -1;
        shell_history_load(shell_saved_line);
    }
    shell_redraw_line(old_len);
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

static int global_key_hotkeys_enabled(void) {
    /* Info is used as a live raw input monitor, so global KEY shortcuts
     * must stay out of the way there. ExpDemo also hands KEY[3:1] to the
     * selected hardware experiment, so shell-level shortcuts must not steal
     * those presses.
     */
    return (active_prog != PROG_DASHBOARD) && (active_prog != PROG_DEMO);
}

static void board_status_refresh(void) {
    uint32_t gpio_in = gpio_read_in();
    uint32_t selected = (uint32_t)shell_selected_prog(gpio_in);
    uint32_t key_bits = (gpio_in >> 18) & 0x7u;
    uint32_t heartbeat = board_status_uptime_seconds() & 0x01u;
    /* flags[0] -> LEDG0 heartbeat, flags[1] -> KEY1 live state */
    uint8_t flags = (uint8_t)((heartbeat & 0x01u) | ((key_bits & 0x01u) << 1));
    uint16_t data = (uint16_t)(((selected & 0x0fu) << 12) |
                               ((key_bits & 0x07u) << 8) |
                               (uint32_t)last_uart_char);

    if (active_prog == PROG_MEMTEST) {
        return; /* memtest owns the LCD/LED fail/pass protocol */
    }

    if (active_prog == PROG_SHELL) {
        board_status_set_program((uint8_t)active_prog, BOARD_STATE_READY, flags, data);
    } else if (!board_status_claimed()) {
        /* Programs that do not actively own LCD/HEX/LED still get a live,
         * deterministic fallback encoding instead of reusing stale GPIO data.
         */
        board_status_set_program((uint8_t)active_prog, BOARD_STATE_LIVE, flags, data);
    }
}

static void enter_program(prog_id_t prog_id) {
    active_prog = prog_id;
    status_dirty = 1;
    board_status_release();
    if ((prog_id < PROG_COUNT) && programs[prog_id] && programs[prog_id]->init) {
        programs[prog_id]->init();
    }
}

static void return_to_shell(void) {
    active_prog = PROG_SHELL;
    status_dirty = 1;
    board_status_release();
    shell_init();
    board_status_refresh();
}

/* ── Shell (built-in) ───────────────────────────────────────────── */

static void shell_init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("DE2Extra Shell v0.2\n", VGA_CYAN);
    vga_puts("Commands: help hello memtest crypto ps2 snake conwaylife info\n", VGA_GRAY);
    vga_puts("          riscvasm expdemo lcdmon cls quit\n", VGA_GRAY);
    vga_puts("Repo: https://github.com/zhangzw0170/DE2Extra.git\n", VGA_GRAY);
    vga_puts("KEY0 reset  KEY1 run SW[3:0] channel  KEY2 shell/home  KEY3 clear/reinit\n\n",
             VGA_GRAY);
    shell_line_pos = 0;
    shell_line[0] = '\0';
    shell_saved_line[0] = '\0';
    shell_history_nav = -1;
    shell_esc_state = 0;
    status_dirty = 1;
    board_status_release();
    shell_prompt();
}

static void shell_update(void) {
    /* Shell is stateless — render happens in input handler */
}

static void shell_show_lcd_shadow(void) {
    char line1[17];
    char line2[17];

    lcd_get_lines(line1, line2);

    vga_puts("LCD shadow (software-side, not physical readback)\n", VGA_CYAN);
    vga_puts("L0: [", VGA_GREEN);
    for (int i = 0; i < 16; i++) {
        vga_putc(line1[i], VGA_WHITE);
    }
    vga_puts("]\n", VGA_GREEN);
    vga_puts("L1: [", VGA_GREEN);
    for (int i = 0; i < 16; i++) {
        vga_putc(line2[i], VGA_WHITE);
    }
    vga_puts("]\n", VGA_GREEN);
}

static void shell_input(char c) {
    if (shell_esc_state == 1) {
        shell_esc_state = (c == '[') ? 2 : 0;
        return;
    }
    if (shell_esc_state == 2) {
        if (c == 'A') {
            shell_history_prev();
        } else if (c == 'B') {
            shell_history_next();
        }
        shell_esc_state = 0;
        return;
    }
    if (c == 27) {
        shell_esc_state = 1;
        return;
    }

    if (c == '\r' || c == '\n') {
        int prompt_already_printed = 0;

        shell_line[shell_line_pos] = '\0';
        vga_putc('\n', VGA_WHITE);

        /* Parse command */
        if (shell_line_pos == 0) {
            /* empty line — show prompt again */
        } else {
            shell_history_push();
            shell_history_nav = -1;
            shell_saved_line[0] = '\0';
        }
        if (shell_line_pos == 0) {
            /* empty line — show prompt again */
        } else if (strcmp(shell_line, "help") == 0) {
            vga_puts("Commands: hello, memtest, crypto, ps2, snake, conwaylife, info, riscvasm, expdemo, lcdmon, cls, quit\n",
                     VGA_GREEN);
        } else if (strcmp(shell_line, "hello") == 0) {
            enter_program(PROG_HELLO);
        } else if (strcmp(shell_line, "memtest") == 0 || strcmp(shell_line, "sdram") == 0 ||
                   strcmp(shell_line, "sdram_test") == 0) {
            enter_program(PROG_MEMTEST);
        } else if (strcmp(shell_line, "crypto") == 0) {
            enter_program(PROG_CRYPTO);
        } else if (strcmp(shell_line, "ps2") == 0 || strcmp(shell_line, "kbd") == 0) {
            enter_program(PROG_PS2);
        } else if (strcmp(shell_line, "snake") == 0) {
            enter_program(PROG_SNAKE);
        } else if (strcmp(shell_line, "conwaylife") == 0 || strcmp(shell_line, "life") == 0) {
            enter_program(PROG_LIFE);
        } else if (strcmp(shell_line, "info") == 0 || strcmp(shell_line, "dash") == 0) {
            enter_program(PROG_INFO);
        } else if (strcmp(shell_line, "riscvasm") == 0 ||
                   strcmp(shell_line, "monitor") == 0 ||
                   strcmp(shell_line, "rv32") == 0) {
            enter_program(PROG_MONITOR);
        } else if (strcmp(shell_line, "expdemo") == 0) {
            enter_program(PROG_DEMO);
        } else if (strcmp(shell_line, "lcdmon") == 0) {
            shell_show_lcd_shadow();
        } else if (strcmp(shell_line, "cls") == 0) {
            shell_init();
            prompt_already_printed = 1;
        } else if (strcmp(shell_line, "quit") == 0 || strcmp(shell_line, "exit") == 0) {
            return_to_shell();
            prompt_already_printed = 1;
        } else {
            vga_puts("? Unknown command. Type 'help'\n", VGA_RED);
        }

        shell_line_pos = 0;
        shell_line[0] = '\0';
        if ((active_prog == PROG_SHELL) && !prompt_already_printed) {
            shell_prompt();
        }
    } else if (c == '\b' || c == 0x7F) {
        if (shell_line_pos > 0) {
            shell_line_pos--;
            shell_line[shell_line_pos] = '\0';
            vga_putc('\b', VGA_WHITE);
        }
    } else if (c >= ' ' && c < 0x7F && shell_line_pos < SHELL_LINE_SIZE - 1) {
        shell_line[shell_line_pos++] = c;
        shell_line[shell_line_pos] = '\0';
        vga_putc(c, VGA_WHITE);
    }
}

/* ── Status Bar ─────────────────────────────────────────────────── */

static void draw_status_bar(void) {
    static const char hex[] = "0123456789ABCDEF";
    static uint32_t last_minute = 0xffffffffu;
    static uint32_t last_clear_epoch = 0xffffffffu;
    uint32_t uptime = board_status_uptime_seconds();
    uint32_t total_minutes = uptime / 60u;
    uint32_t hours = total_minutes / 60u;
    uint32_t minutes = total_minutes % 60u;
    uint32_t clear_epoch = vga_clear_epoch();
    int saved_col;
    int saved_row;

    if (total_minutes != last_minute) {
        status_dirty = 1;
        last_minute = total_minutes;
    }
    if (clear_epoch != last_clear_epoch) {
        status_dirty = 1;
        last_clear_epoch = clear_epoch;
    }

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
    for (int i = vga_col(); i < VGA_COLS - 10; i++) {
        vga_putc(' ', VGA_BLACK);
    }
    vga_puts("Up ", VGA_GRAY);
    vga_putc(hex[(hours / 100u) % 10u], VGA_YELLOW);
    vga_putc(hex[(hours / 10u) % 10u], VGA_YELLOW);
    vga_putc(hex[hours % 10u], VGA_YELLOW);
    vga_putc(':', VGA_WHITE);
    vga_putc(hex[(minutes / 10u) % 10u], VGA_YELLOW);
    vga_putc(hex[minutes % 10u], VGA_YELLOW);
    for (int i = vga_col(); i < VGA_COLS; i++) {
        vga_putc(' ', VGA_BLACK);
    }
    vga_goto(saved_col, saved_row);
    status_dirty = 0;
}

/* ── IR Command Handler ─────────────────────────────────────────── */

#ifndef LOCAL_BUILD
static void handle_ir(uint8_t cmd) {
    /* Forward IR input to active program first */
    const program_t *prog = programs[active_prog];
    if (prog && prog->ir_input) {
        prog->ir_input(cmd);
        return;
    }

    /* Global IR commands: digits follow the shell's internal channel IDs so
     * the remote key, status bar channel, and LCD program ID stay aligned.
     * A remains the dedicated shortcut for expdemo (program 0xA).
     */
    prog_id_t new_prog = PROG_SHELL;
    switch (cmd) {
        case IR_BTN_0:
        case IR_BTN_RETURN:
            return_to_shell();
            return; /* 0 / RETURN */
        case IR_BTN_1: new_prog = PROG_HELLO;     break;
        case IR_BTN_2: new_prog = PROG_MEMTEST;   break;
        case IR_BTN_3: new_prog = PROG_CRYPTO;    break;
        case IR_BTN_4: new_prog = PROG_PS2;       break;
        case IR_BTN_5: new_prog = PROG_SNAKE;     break;
        case IR_BTN_6: new_prog = PROG_LIFE;      break;
        case IR_BTN_7: new_prog = PROG_INFO;      break;
        case IR_BTN_8: new_prog = PROG_INFO;      break;
        case IR_BTN_9: new_prog = PROG_MONITOR;   break;
        case IR_BTN_A: new_prog = PROG_DEMO;      break;
        case IR_BTN_CH_DN:
            if (active_prog > 0) {
                new_prog = active_prog - 1;
                break;
            }
            return;  /* CH-: prev */
        case IR_BTN_CH_UP:
            if (active_prog < PROG_COUNT - 1) {
                new_prog = active_prog + 1;
                break;
            }
            return; /* CH+: next */
        default:   return;  /* unknown key */
    }

    if (new_prog == PROG_SHELL) {
        return_to_shell();
    } else {
        enter_program(new_prog);
    }
}
#endif

static void handle_keys(void) {
    uint32_t gpio_in = gpio_read_in();
    uint8_t key_bits = (uint8_t)((gpio_in >> 18) & 0x07u);
    uint8_t pressed = (uint8_t)(key_bits & (uint8_t)(~prev_key_bits));
    prog_id_t quick_prog = shell_selected_prog(gpio_in);
    const program_t *prog = programs[active_prog];

    prev_key_bits = key_bits;

    if (!global_key_hotkeys_enabled()) {
        return;
    }

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

#ifndef LOCAL_BUILD
static void handle_ir_events(void) {
    uint32_t gpio_in = gpio_read_in();
    uint8_t ir_toggle = (uint8_t)((gpio_in >> 31) & 0x01u);
    uint8_t ir_cmd = (uint8_t)((gpio_in >> 22) & 0xffu);

    if (ir_toggle != prev_ir_toggle) {
        prev_ir_toggle = ir_toggle;
        last_ir_cmd = ir_cmd;
        handle_ir(ir_cmd);
    }
}
#endif

/* ── Main ──────────────────────────────────────────────────────── */

#ifndef LOCAL_BUILD
int main(void) {
    neorv32_rte_setup();
    uart_init();
#else
int main(void) {
#endif
    gpio_write_out(0);
    board_status_init();
    vga_init();
    shell_init();
    board_status_refresh();
    draw_status_bar();

    while (1) {
        handle_keys();
#ifndef LOCAL_BUILD
        handle_ir_events();
#endif

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
