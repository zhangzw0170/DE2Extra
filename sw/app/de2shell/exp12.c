/* exp12.c — Simple 5-Instruction CPU status */
#include "vga_hal.h"
#include <stdint.h>

static int active = 0;

static void init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("Exp 12: Simple CPU (5 instructions)\n", VGA_CYAN);
    vga_puts("===================================\n", VGA_WHITE);
    vga_puts("Architecture: Single Accumulator, 16-bit instruction\n", VGA_GRAY);
    vga_puts("  opcode[15:8] | address[7:0]\n", VGA_GRAY);
    vga_puts("Instructions: ADD, STORE, LOAD, JUMP, JNEG\n", VGA_GRAY);
    vga_puts("\nControls:\n", VGA_GRAY);
    vga_puts("  KEY2 = Auto/Manual mode (LEDR17)\n", VGA_GREEN);
    vga_puts("  KEY1 = Step (Manual mode)\n", VGA_GREEN);
    vga_puts("  KEY0 = Reset\n", VGA_GREEN);
    vga_puts("  SW16 = LCD detail mode\n", VGA_GREEN);
    vga_puts("\nHEX7-6=IR  HEX5-4=PC  HEX3-0=AC  LEDR[7:0]=AC\n", VGA_YELLOW);
    vga_puts("Demo: A = 3 + 5 = 8 (with JNEG branch test)\n", VGA_YELLOW);
    vga_puts("\nOperate switches on DE2-115 board.\n", VGA_YELLOW);
    vga_puts("Press 'q' to return to shell.\n", VGA_GRAY);
    active = 1;
}

static void update(void) { if (!active) return; }
static void input(char c) { if (c == 'q' || c == 'Q') active = 0; }
static int finish(void) { return !active; }

const program_t prog_exp12 = {
    "Exp12", "Simple CPU — 5-instruction processor",
    init, update, input, NULL, finish
};
