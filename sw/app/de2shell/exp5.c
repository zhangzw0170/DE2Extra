/* exp5.c — FSM Sequence Detector status */
#include "vga_hal.h"
#include <stdint.h>

static int active = 0;

static void init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("Exp 5: FSM Sequence Detector (Moore/Mealy)\n", VGA_CYAN);
    vga_puts("==========================================\n", VGA_WHITE);
    vga_puts("Detects 4 consecutive 0s or 4 consecutive 1s.\n", VGA_GRAY);
    vga_puts("Controls:\n", VGA_GRAY);
    vga_puts("  SW1     = Input value (UP=1, DOWN=0)\n", VGA_GREEN);
    vga_puts("  KEY0    = Advance state (clock)\n", VGA_GREEN);
    vga_puts("  LEDR[7:0] = Input history shift register\n", VGA_GREEN);
    vga_puts("  LEDG8   = z=1 (sequence detected)\n", VGA_GREEN);
    vga_puts("\nOperate switches on DE2-115 board.\n", VGA_YELLOW);
    vga_puts("Press 'q' to return to shell.\n", VGA_GRAY);
    active = 1;
}

static void update(void) { if (!active) return; }
static void input(char c) { if (c == 'q' || c == 'Q') active = 0; }
static int finish(void) { return !active; }

const program_t prog_exp5 = {
    "Exp5", "FSM Sequence Detector — 4-bit pattern",
    init, update, input, NULL, finish
};
