/* hello.c — Phase 0 经典演示: LED 跑马灯 + 秒计数器
 *
 * LEDR[15:0] 跑马灯, HEX 显示十六进制值, 秒计数器
 * 在 LOCAL_BUILD 下用 VGA 模拟显示
 */
#include "vga_hal.h"
#include "gpio_hal.h"
#include "board_status.h"

#define HELLO_PROG_ID 1u

static uint32_t led_idx;
static uint32_t seconds;
static int tick;
static int done;

static void init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("DE2Extra — NEORV32 RISC-V alive!\n", VGA_CYAN);
    vga_puts("================================\n", VGA_WHITE);
    vga_puts("CPU:    RV32IMC + Zk*\n", VGA_GREEN);
    vga_puts("Board:  DE2-115 (Cyclone IV E)\n", VGA_GREEN);
    vga_puts("\n", VGA_WHITE);

    led_idx = 0;
    seconds = 0;
    tick = 0;
    done = 0;

    vga_puts("LED chasing... press 'q' to quit\n", VGA_GRAY);
}

static void update(void) {
    if (done) return;

    tick++;

    /* LED 跑马灯 */
    uint32_t led_pattern = 1u << led_idx;

#ifndef LOCAL_BUILD
    /* Keep the shell-status protocol in the upper bits so LCD stays in host mode. */
    board_status_set_program(HELLO_PROG_ID, BOARD_STATE_RUN,
                             (uint8_t)(seconds & 0x0fu),
                             (uint16_t)led_pattern);
#endif

    /* VGA 上显示状态 */
    vga_goto(0, 5);
    vga_puts("LED:  ", VGA_YELLOW);
    for (int i = 15; i >= 0; i--) {
        vga_putc((led_pattern >> i) & 1 ? '*' : '.', VGA_WHITE);
    }
    vga_puts("  HEX: ", VGA_YELLOW);

    /* 显示秒计数器 */
    uint32_t hex_val = led_pattern;
    const char hex_chars[] = "0123456789ABCDEF";
    for (int i = 7; i >= 0; i--) {
        vga_putc(hex_chars[(hex_val >> (i * 4)) & 0xF], VGA_CYAN);
        if (i == 4) vga_putc(' ', VGA_WHITE);
    }

    vga_puts("  SEC: ", VGA_YELLOW);
    vga_putc(hex_chars[(seconds >> 4) & 0xF], VGA_CYAN);
    vga_putc(hex_chars[seconds & 0xF], VGA_CYAN);

    led_idx++;
    if (led_idx >= 16) {
        led_idx = 0;
        seconds++;
    }

    /* 延时 */
#ifdef LOCAL_BUILD
    for (volatile int d = 0; d < 2000000; d++) {}
#else
    for (volatile int d = 0; d < 50000; d++) {}
#endif
}

static void input(char c) {
    (void)c;
}

static int finish(void) { return done; }

const program_t prog_hello = {
    "Hello", "Phase 0 LED chasing demo",
    init, update, input, NULL, finish
};
