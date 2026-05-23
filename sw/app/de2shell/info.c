/* info.c — System Information page */
#include "vga_hal.h"

static void init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("DE2Extra System Info\n", VGA_CYAN);
    vga_puts("===================\n", VGA_WHITE);
    vga_puts("CPU:    NEORV32 RV32IMC @ 50MHz\n", VGA_GREEN);
    vga_puts("Memory: IMEM 32KB  DMEM 16KB  SDRAM 128MB\n", VGA_GREEN);
    vga_puts("VGA:    640x480@60Hz  80x25 text\n", VGA_GREEN);
    vga_puts("Input:  UART + PS/2 + IR Remote\n", VGA_GREEN);
    vga_puts("Crypto: AES-128 SHA-256 SHA-512 SM4 SM3\n", VGA_GREEN);
    vga_puts("\nPress 'q' to return.\n", VGA_GRAY);
}
static void update(void) {}
static void input(char c) {
    if (c == 'q' || c == 'Q') vga_clear();
}
static int finish(void) { return 0; }

const program_t prog_info = {
    "Info", "System information",
    init, update, input, NULL, finish
};
