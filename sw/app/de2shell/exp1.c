/* exp1.c — 3-8 Decoder live status (SW[2:0] → LEDR[7:0]) */
#include "vga_hal.h"
#include "gpio_hal.h"
#include <stdint.h>

static int active = 0;

static void init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("Exp 1: 3-8 Decoder (74HC138)\n", VGA_CYAN);
    vga_puts("===============================\n", VGA_WHITE);
    vga_puts("SW[2:0] = address input (G1=1, G2A=0, G2B=0)\n", VGA_GRAY);
    vga_puts("LEDR[7:0] = active-low output (0=ON)\n", VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    active = 1;
}

static void update(void) {
    if (!active) return;
    uint32_t in  = gpio_read_in();
    uint32_t out = gpio_read_out();
    int sw = in & 0x07;  /* SW[2:0] */

    vga_goto(0, 5);
    vga_puts("SW[2:0] = ", VGA_WHITE);
    vga_putc('0' + ((sw >> 2) & 1), VGA_YELLOW);
    vga_putc('0' + ((sw >> 1) & 1), VGA_YELLOW);
    vga_putc('0' + (sw & 1), VGA_YELLOW);

    vga_goto(0, 6);
    vga_puts("Expected Output: ", VGA_WHITE);
    /* 3-8 decode: only bit 'sw' is 0 (active-low) */
    int expected = (1 << sw) & 0xFF;
    for (int i = 7; i >= 0; i--) {
        vga_putc((expected & (1 << i)) ? '0' : '1', VGA_GREEN);
    }

    vga_goto(0, 7);
    vga_puts("Actual LEDR[7:0]: ", VGA_WHITE);
    for (int i = 7; i >= 0; i--) {
        vga_putc((out & (1 << i)) ? '1' : '0',  /* LEDR[7:0] = GPIO_OUT[7:0] */
                 VGA_YELLOW);
    }

    vga_goto(0, 9);
    vga_puts("G1=1 G2A=0 G2B=0  (enable active)\n", VGA_GRAY);
    vga_puts("Press 'q' to return to shell.\n", VGA_GRAY);
}

static void input(char c) {
    if (c == 'q' || c == 'Q') active = 0;
}

static int finish(void) { return !active; }

const program_t prog_exp1 = {
    "Exp1", "3-8 Decoder — SW->LEDR status",
    init, update, input, NULL, finish
};
