/* dashboard.c — System Dashboard stub */
#include "vga_hal.h"

static int done;

static void init(void) {
    done = 0;
    vga_clear();
    vga_goto(0, 0);
    vga_puts("System Dashboard\n", VGA_CYAN);
    vga_puts("SW: 0000  LEDR: 0000  HEX: 00000000\n", VGA_GREEN);
    vga_puts("KEY: ----  IR: --  CLOCK: --:--:--\n", VGA_GREEN);
    vga_puts("Press 'q' to return.\n", VGA_GRAY);
}
static void update(void) {}
static void input(char c) {
    if (c == 'q' || c == 'Q') {
        done = 1;
    }
}
static int finish(void) { return done; }

const program_t prog_dashboard = {
    "Dashboard", "System I/O monitor — SW/LED/HEX/KEY/IR",
    init, update, input, NULL, finish
};
