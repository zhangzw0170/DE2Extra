/* life.c — Conway Game of Life stub */
#include "vga_hal.h"

static void init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("Conway's Game of Life\n", VGA_CYAN);
    vga_puts("(porting from game_life)\n", VGA_GRAY);
}
static void update(void) {}
static void input(char c) {
    if (c == 'q' || c == 'Q') vga_clear();
}
static int finish(void) { return 0; }

const program_t prog_life = {
    "Life", "Conway Game of Life — B3/S23",
    init, update, input, NULL, finish
};
