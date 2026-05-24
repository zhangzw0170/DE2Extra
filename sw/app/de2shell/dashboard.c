/* dashboard.c — System Dashboard */
#include "board_status.h"
#include "gpio_hal.h"
#include "vga_hal.h"

static int done;

static void put_hex_digit(uint8_t val, uint8_t color) {
    static const char hex[] = "0123456789ABCDEF";
    vga_putc(hex[val & 0x0f], color);
}

static void put_hex8(uint8_t val, uint8_t color) {
    put_hex_digit((uint8_t)(val >> 4), color);
    put_hex_digit(val, color);
}

static void put_hex16(uint16_t val, uint8_t color) {
    put_hex8((uint8_t)(val >> 8), color);
    put_hex8((uint8_t)val, color);
}

static void put_hex32(uint32_t val, uint8_t color) {
    put_hex16((uint16_t)(val >> 16), color);
    put_hex16((uint16_t)val, color);
}

static void put_bits(uint32_t value, int width, uint8_t color) {
    for (int i = width - 1; i >= 0; i--) {
        vga_putc((value & (1u << i)) ? '1' : '0', color);
    }
}

static void init(void) {
    done = 0;
    vga_clear();
    vga_goto(0, 0);
    vga_puts("System Dashboard\n", VGA_CYAN);
    vga_puts("================\n", VGA_WHITE);
    vga_puts("Live board ownership demo: dashboard now drives LCD/HEX/LED.\n", VGA_GRAY);
    vga_puts("Press 'q' to return.\n", VGA_GRAY);
}

static void update(void) {
    uint32_t gpio_in;
    uint32_t gpio_out;
    uint32_t uptime;
    uint8_t key_bits;

    if (done) {
        return;
    }

    gpio_in = gpio_read_in();
    key_bits = (uint8_t)((gpio_in >> 18) & 0x07u);
    uptime = board_status_uptime_seconds();

    board_status_set_program(7u, BOARD_STATE_LIVE, key_bits, (uint16_t)gpio_in);
    gpio_out = gpio_read_out();

    vga_goto(0, 5);
    vga_puts("SW[17:0] : ", VGA_WHITE);
    put_bits(gpio_in & 0x3ffffu, 18, VGA_YELLOW);
    vga_puts("  (low16 mirrored to LEDR/HEX)\n", VGA_GRAY);

    vga_goto(0, 6);
    vga_puts("KEY[3:1] : ", VGA_WHITE);
    put_bits(key_bits, 3, VGA_YELLOW);
    vga_puts("  LEDG[2:0] follows these bits\n", VGA_GRAY);

    vga_goto(0, 7);
    vga_puts("GPIO OUT : 0x", VGA_WHITE);
    put_hex32(gpio_out, VGA_CYAN);
    vga_puts("  LCD = CH7 DASH LIVE\n", VGA_GREEN);

    vga_goto(0, 8);
    vga_puts("HEX view : 0x", VGA_WHITE);
    put_hex16((uint16_t)gpio_in, VGA_YELLOW);
    vga_puts("  Flags=", VGA_WHITE);
    put_hex8(key_bits, VGA_YELLOW);

    vga_goto(0, 10);
    vga_puts("Uptime   : ", VGA_WHITE);
    vga_puthex32(uptime);
    vga_puts(" s\n", VGA_GREEN);
}

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
