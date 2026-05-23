/* exp4.c — 32x8 Dual-Port RAM status display */
#include "vga_hal.h"
#include <stdint.h>

static int active = 0;

static void init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("Exp 4: 32x8 Dual-Port RAM (VHDL Behavior)\n", VGA_CYAN);
    vga_puts("==========================================\n", VGA_WHITE);
    vga_puts("Controls:\n", VGA_GRAY);
    vga_puts("  SW17    = Mode (UP=Write, DOWN=Read)\n", VGA_GREEN);
    vga_puts("  SW[4:0] = Address (0-31)\n", VGA_GREEN);
    vga_puts("  SW[12:5] = Write Data\n", VGA_GREEN);
    vga_puts("  KEY0    = Write strobe (LEDG8 confirms)\n", VGA_GREEN);
    vga_puts("\n[ Status will display here when GPIO is connected ]\n", VGA_GRAY);
    vga_puts("\nOperate switches on DE2-115 board.\n", VGA_YELLOW);
    vga_puts("Press 'q' to return to shell.\n", VGA_GRAY);
    active = 1;
}

static void update(void) {
    if (!active) return;
    /* Future: read GPIO and show addr/data/mode */
}

static void input(char c) {
    if (c == 'q' || c == 'Q') active = 0;
}

static int finish(void) { return !active; }

const program_t prog_exp4 = {
    "Exp4", "32x8 Dual-Port RAM — BRAM demo",
    init, update, input, NULL, finish
};
