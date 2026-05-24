/* dashboard.c — System Dashboard
 *
 * Shows live board state: SW, KEY, GPIO, uptime, and last IR command.
 * LCD: "CH7 DASH LIVE", HEX: prog/state/keys/IR
 */
#include "board_status.h"
#include "gpio_hal.h"
#include "vga_hal.h"
#include <stdint.h>

#ifndef LOCAL_BUILD
typedef volatile struct {
    uint32_t data;
    uint32_t status;
} ir_regs_t;

#define IR_DBG ((ir_regs_t*)0xF0009000u)
#endif

/* Shared IR command from main.c */
extern uint8_t last_ir_cmd;

static int done;

static const char *ir_label(uint8_t cmd) {
    switch (cmd) {
        case 0x0F: return "A";
        case 0x13: return "B";
        case 0x10: return "C";
        case 0x12: return "POWER";
        case 0x01: return "1";
        case 0x02: return "2";
        case 0x03: return "3";
        case 0x1A: return "CH+";
        case 0x04: return "4";
        case 0x05: return "5";
        case 0x06: return "6";
        case 0x1E: return "CH-";
        case 0x07: return "7";
        case 0x08: return "8";
        case 0x09: return "9";
        case 0x1B: return "VOL+";
        case 0x11: return "MENU";
        case 0x00: return "0";
        case 0x17: return "RETURN";
        case 0x1F: return "VOL-";
        case 0x16: return "PLAY";
        case 0x14: return "ADJ<";
        case 0x18: return "ADJ>";
        case 0x0C: return "MUTE";
        default:   return "?";
    }
}

static void put_hex_digit(uint8_t val, uint16_t color) {
    static const char hex[] = "0123456789ABCDEF";
    vga_putc(hex[val & 0x0f], color);
}

static void put_hex8(uint8_t val, uint16_t color) {
    put_hex_digit((uint8_t)(val >> 4), color);
    put_hex_digit(val, color);
}

static void put_hex16(uint16_t val, uint16_t color) {
    put_hex8((uint8_t)(val >> 8), color);
    put_hex8((uint8_t)val, color);
}

static void put_hex32(uint32_t val, uint16_t color) {
    put_hex16((uint16_t)(val >> 16), color);
    put_hex16((uint16_t)val, color);
}

static void put_bits(uint32_t value, int width, uint16_t color) {
    for (int i = width - 1; i >= 0; i--)
        vga_putc((value & (1u << i)) ? '1' : '0', color);
}

static void init(void) {
    done = 0;
    vga_clear();
    vga_goto(0, 0);
    vga_puts("System Dashboard\n", VGA_CYAN);
    vga_puts("================\n", VGA_WHITE);
    vga_puts("Live board state monitor.\n", VGA_GRAY);
    vga_puts("KEY0 is wired to hardware reset; software only samples KEY[3:1].\n", VGA_GRAY);
    vga_puts("Global KEY shortcuts are disabled here so KEY[3:1] can be observed raw.\n", VGA_GRAY);
    vga_puts("Press 'q' to return.\n", VGA_GRAY);
}

static void update(void) {
    uint32_t gpio_in, gpio_out, uptime;
    uint32_t ir_data = 0;
    uint32_t ir_status = 0;
    uint8_t key_bits;
    uint8_t raw_ir;
    uint8_t dbg_valid;
    uint8_t dbg_cmd;

    if (done) return;

    gpio_in = gpio_read_in();
    key_bits = (uint8_t)((gpio_in >> 18) & 0x07u);
    raw_ir = (uint8_t)((gpio_in >> 21) & 0x01u);
    dbg_cmd = (uint8_t)((gpio_in >> 22) & 0xffu);
    dbg_valid = (uint8_t)((gpio_in >> 30) & 0x01u);
    uptime = board_status_uptime_seconds();

#ifndef LOCAL_BUILD
    ir_data = IR_DBG->data;
    ir_status = IR_DBG->status;
#endif

    board_status_set_program(7u, BOARD_STATE_LIVE, key_bits,
                             (uint16_t)((last_ir_cmd << 8) | key_bits));
    gpio_out = gpio_read_out();

    vga_goto(0, 5);
    vga_puts("SW[17:0] : ", VGA_WHITE);
    put_bits(gpio_in & 0x3ffffu, 18, VGA_YELLOW);
    vga_puts("\n", VGA_GRAY);

    vga_goto(0, 6);
    vga_puts("KEY[3:1] pressed : ", VGA_WHITE);
    put_bits(key_bits, 3, VGA_YELLOW);
    vga_puts("\n", VGA_GRAY);

    vga_goto(0, 7);
    vga_puts("KEY0     : hardware reset key (not readable after reset release)\n", VGA_GRAY);

    vga_goto(0, 8);
    vga_puts("GPIO OUT : 0x", VGA_WHITE);
    put_hex32(gpio_out, VGA_CYAN);
    vga_puts("\n", VGA_GRAY);

    vga_goto(0, 9);
    vga_puts("Last IR  : ", VGA_WHITE);
    if (last_ir_cmd != 0 || dbg_valid) {
        put_hex8(last_ir_cmd, VGA_YELLOW);
        vga_puts("  ", VGA_WHITE);
        vga_puts(ir_label(last_ir_cmd), VGA_GREEN);
    } else {
        vga_puts("-- (none)", VGA_GRAY);
    }

    vga_goto(0, 10);
    vga_puts("IR RAW   : ", VGA_WHITE);
    vga_putc(raw_ir ? '1' : '0', raw_ir ? VGA_GREEN : VGA_YELLOW);
    vga_puts("  DBG V/CMD: ", VGA_WHITE);
    vga_putc(dbg_valid ? '1' : '0', dbg_valid ? VGA_GREEN : VGA_YELLOW);
    vga_puts(" / 0x", VGA_WHITE);
    put_hex8(dbg_cmd, VGA_CYAN);
    vga_puts("\n", VGA_GRAY);

    vga_goto(0, 11);
    vga_puts("IR REG   : DATA=0x", VGA_WHITE);
    put_hex32(ir_data, VGA_CYAN);
    vga_puts("  ST=0x", VGA_WHITE);
    put_hex32(ir_status, VGA_CYAN);
    vga_puts("\n", VGA_GRAY);

    vga_goto(0, 13);
    vga_puts("Uptime   : ", VGA_WHITE);
    put_hex32(uptime, VGA_CYAN);
    vga_puts(" s\n", VGA_GREEN);
}

static void input(char c) {
    if (c == 'q' || c == 'Q') done = 1;
}

static int finish(void) { return done; }

const program_t prog_dashboard = {
    "Dashboard", "System I/O monitor — SW/LED/HEX/KEY/IR",
    init, update, input, NULL, finish
};
