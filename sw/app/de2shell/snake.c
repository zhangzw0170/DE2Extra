/* snake.c — Snake game stub */
#include "vga_hal.h"
#include <stdint.h>

static void init(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("Snake Game\n", VGA_YELLOW);
    vga_puts("(porting from game_snake)\n", VGA_GRAY);
}

static void update(void) {}
static void input(char c) {
    if (c == 'q' || c == 'Q') vga_clear();
}
static int finish(void) { return 0; }

const program_t prog_snake = {
    "Snake", "Snake Game — eat the food!",
    init, update, input, NULL, finish
};
