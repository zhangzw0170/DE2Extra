/* info.c — System Information page */
#include "vga_hal.h"

static int done;

static void init(void) {
    done = 0;
    vga_clear();
    vga_goto(0, 0);
    vga_puts("DE2Extra System Info\n", VGA_CYAN);
    vga_puts("===================\n", VGA_WHITE);
    vga_puts("CPU:    NEORV32 RV32IMC + Zk* @ 50MHz\n", VGA_GREEN);
    vga_puts("Memory: IMEM 64KB  DMEM 16KB  SDRAM 128MB\n", VGA_GREEN);
    vga_puts("VGA:    640x480@60Hz  80x25 text\n", VGA_GREEN);
    vga_puts("Input:  UART + PS/2 + IR Remote\n", VGA_GREEN);
    vga_puts("Crypto: AES-128 SHA-256 SHA-512 SM4 SM3\n", VGA_GREEN);
    vga_puts("\nPress 'q' to return.\n", VGA_GRAY);
}
static void update(void) {}
static void input(char c) {
    if (c == 'q' || c == 'Q') {
        done = 1;
    }
}
static int finish(void) { return done; }

const program_t prog_info = {
    "Info", "System information",
    init, update, input, NULL, finish
};
