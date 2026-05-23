/* dashboard.c — System Dashboard stub */
#include "vga_hal.h"

static void init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("System Dashboard\n", VGA_CYAN);
    vga_puts("SW: 0000  LEDR: 0000  HEX: 00000000\n", VGA_GREEN);
    vga_puts("KEY: ----  IR: --  CLOCK: --:--:--\n", VGA_GREEN);
}
static void update(void) {}
static void input(char c) {
    if (c == 'q' || c == 'Q') vga_clear();
}
static int finish(void) { return 0; }

const program_t prog_dashboard = {
    "Dashboard", "System I/O monitor — SW/LED/HEX/KEY/IR",
    init, update, input, NULL, finish
};
