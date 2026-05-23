/* crypto.c — Crypto CLI terminal stub */
#include "vga_hal.h"
#include <stdint.h>

static void init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("Crypto Terminal\n", VGA_CYAN);
    vga_puts("(AES/SHA/SM4/SM3 — porting from phase2a)\n", VGA_GRAY);
    vga_puts("\nPress 'q' to return to shell.\n", VGA_GREEN);
}

static void update(void) {}
static void input(char c) {
    if (c == 'q' || c == 'Q') {
        vga_clear();
    }
}
static int finish(void) { return 0; }

const program_t prog_crypto = {
    "Crypto", "Crypto CLI — AES/SHA/SM4/SM3",
    init, update, input, NULL, finish
};
