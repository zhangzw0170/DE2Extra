/* demo.c — expdemo unified hardware experiment entry */
#include "board_status.h"
#include "gpio_hal.h"
#include "vga_hal.h"
#include <stdint.h>

typedef volatile struct {
    uint32_t channel;
    uint32_t status;
    uint32_t exp12_snap0;
    uint32_t exp12_ac;
    uint32_t exp12_ir;
    uint32_t exp12_step;
    uint32_t exp13_state;
} expdemo_regs_t;

#ifndef LOCAL_BUILD
typedef volatile struct {
    uint32_t data;
    uint32_t status;
} ir_regs_t;

#define EXPDEMO ((expdemo_regs_t*)0xF0010000u)
#define IR_DBG  ((ir_regs_t*)0xF000C000u)
#endif

#define IR_BTN_A       0x0Fu
#define IR_BTN_0       0x00u
#define IR_BTN_1       0x01u
#define IR_BTN_2       0x02u
#define IR_BTN_3       0x03u
#define IR_BTN_4       0x04u
#define IR_BTN_5       0x05u
#define IR_BTN_6       0x06u
#define IR_BTN_7       0x07u
#define IR_BTN_8       0x08u
#define IR_BTN_9       0x09u
#define IR_BTN_MENU    0x11u
#define IR_BTN_RETURN  0x17u
#define IR_BTN_CH_UP   0x1Au
#define IR_BTN_CH_DN   0x1Eu
#define IR_BTN_PLAY    0x16u

typedef struct {
    uint8_t id;
    const char *name;
    const char *detail;
    const char *sw_desc;
    const char *key_desc;
    const char *io_desc;
} exp_entry_t;

typedef struct {
    uint8_t hw_channel;
    uint8_t key_bits;
    uint8_t raw_ir;
    uint8_t dbg_valid;
    uint8_t dbg_cmd;
    uint8_t last_ir;
    uint32_t gpio_in;
    uint32_t status;
    uint32_t uptime;
    uint32_t ir_data;
    uint32_t ir_status;
    uint32_t exp12_snap0;
    uint32_t exp12_ac;
    uint32_t exp12_ir;
    uint32_t exp12_step;
    uint32_t exp13_state;
} expdemo_monitor_t;

static const exp_entry_t exp_entries[] = {
    {1,  "Exp1",  "3-8 Decoder",
     "SW[2:0]=ABC, SW5=G1, SW4:3=G2A/G2B",
     "KEY: none; KEY0 stays board reset",
     "LEDR[7:0] = active-low decoder output"},
    {2,  "Exp2",  "LED Patterns",
     "SW0 enables the light-show engine",
     "KEY1 = next pattern; KEY0 reserved",
     "LEDR[17:0] show pattern, HEX returns OFF / CLr / LFx"},
    {3,  "Exp3",  "7-Segment Scan",
     "SW17:16 choose sub-mode; clock mode also uses SW15:14 and SW7:0",
     "KEY1 = reset, KEY2 = write minute, KEY3 = write hour",
     "Second-write on original KEY0 is removed in expdemo"},
    {4,  "Exp4",  "Dual-Port RAM",
     "SW17 write/read, SW15:11 addr, SW7:0 data",
     "KEY1 = one write pulse in write mode",
     "HEX shows addr/data, LEDG8 is write-ack"},
    {5,  "Exp5",  "FSM Detector",
     "SW0 = input w, SW17:16 choose FSM",
     "KEY1 = reset FSM state",
     "LEDG shows state, LEDR1:0 show detection"},
    {9,  "Exp9",  "UART",
     "SW7:0 choose TX byte",
     "KEY1 = send the current SW byte",
     "HEX5:4 RX, HEX1:0 TX, LEDR RX, LEDG TX"},
    {11, "Exp11", "Sine DDS",
     "SW17 selects LED/SignalTap mode, SW7:0 is sine DDS fword",
     "KEY1 = DDS reset",
     "LEDR[9:0] shows DDS amplitude sample"},
    {12, "Exp12", "Simple CPU",
     "SW16 toggles LCD detail mode",
     "KEY1 = reset, KEY2 = single-step, KEY3 = auto/manual",
     "Top area shows CPU state; lower trace area mirrors LCD line pairs"},
    {13, "Exp13", "LCD SoC",
     "SW7:0 feed the LCD demo / data source",
     "KEY1 = next LCD message page",
     "VGA/serial mirrors the 16x2 LCD layout directly"}
};

/* Shared IR command from main.c */
extern uint8_t last_ir_cmd;

static int active = 0;
static int running = 0;
static int dirty = 0;
static int typed_value = -1;
static int last_hw_channel = -1;
static uint8_t selected_channel = 1;
static expdemo_monitor_t last_monitor;
static int have_monitor = 0;
static char exp12_hist0[8][17];
static char exp12_hist1[8][17];
static int exp12_hist_count = 0;
static uint8_t exp9_rx_hist[16];
static int exp9_rx_count = 0;
static uint8_t exp9_last_tx = 0;
static uint8_t exp9_last_rx = 0;
static int exp9_have_byte = 0;

#ifdef LOCAL_BUILD
static uint32_t sim_channel = 0;
static uint32_t sim_status = 0;
static uint32_t sim_exp12_snap0 = 0;
static uint32_t sim_exp12_ac = 0;
static uint32_t sim_exp12_ir = 0;
static uint32_t sim_exp12_step = 0;
static uint32_t sim_exp13_state = 0;
#endif

static int exp_count(void) {
    return (int)(sizeof(exp_entries) / sizeof(exp_entries[0]));
}

static int valid_channel(uint8_t ch) {
    int i;
    for (i = 0; i < exp_count(); i++) {
        if (exp_entries[i].id == ch) {
            return 1;
        }
    }
    return ch == 0;
}

static const exp_entry_t* find_entry(uint8_t ch) {
    int i;
    for (i = 0; i < exp_count(); i++) {
        if (exp_entries[i].id == ch) {
            return &exp_entries[i];
        }
    }
    return NULL;
}

static uint8_t next_channel(uint8_t ch) {
    int i;
    for (i = 0; i < exp_count(); i++) {
        if (exp_entries[i].id > ch) {
            return exp_entries[i].id;
        }
    }
    return exp_entries[0].id;
}

static uint8_t prev_channel(uint8_t ch) {
    int i;
    for (i = exp_count() - 1; i >= 0; i--) {
        if (exp_entries[i].id < ch) {
            return exp_entries[i].id;
        }
    }
    return exp_entries[exp_count() - 1].id;
}

static void put_dec_u8(uint8_t v, uint16_t color) {
    if (v >= 100) {
        vga_putc('0' + (char)(v / 100), color);
        vga_putc('0' + (char)((v / 10) % 10), color);
        vga_putc('0' + (char)(v % 10), color);
    } else if (v >= 10) {
        vga_putc('0' + (char)(v / 10), color);
        vga_putc('0' + (char)(v % 10), color);
    } else {
        vga_putc('0' + (char)v, color);
    }
}

static void put_dec_u32(uint32_t v, uint16_t color) {
    char buf[10];
    int n = 0;

    if (v == 0u) {
        vga_putc('0', color);
        return;
    }

    while ((v != 0u) && (n < (int)sizeof(buf))) {
        buf[n++] = (char)('0' + (v % 10u));
        v /= 10u;
    }
    while (n > 0) {
        vga_putc(buf[--n], color);
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
    int i;
    for (i = width - 1; i >= 0; i--) {
        vga_putc((value & (1u << i)) ? '1' : '0', color);
    }
}

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

static char hex_digit_char(uint8_t val) {
    static const char hex[] = "0123456789ABCDEF";
    return hex[val & 0x0fu];
}

static void fill_spaces(char *buf) {
    int i;
    for (i = 0; i < 16; i++) {
        buf[i] = ' ';
    }
    buf[16] = '\0';
}

static void copy_line16(char *dst, const char *src) {
    int i;
    for (i = 0; i < 16; i++) {
        dst[i] = src[i];
    }
    dst[16] = '\0';
}

static int same_line16(const char *a, const char *b) {
    int i;
    for (i = 0; i < 16; i++) {
        if (a[i] != b[i]) {
            return 0;
        }
    }
    return 1;
}

static void write_text(char *buf, int pos, const char *text) {
    int i = 0;
    while (text[i] && (pos + i) < 16) {
        buf[pos + i] = text[i];
        i++;
    }
}

static void reset_exp12_history(void) {
    int i;
    for (i = 0; i < 8; i++) {
        fill_spaces(exp12_hist0[i]);
        fill_spaces(exp12_hist1[i]);
    }
    exp12_hist_count = 0;
}

static void reset_exp9_history(void) {
    int i;
    for (i = 0; i < (int)(sizeof(exp9_rx_hist) / sizeof(exp9_rx_hist[0])); i++) {
        exp9_rx_hist[i] = 0;
    }
    exp9_rx_count = 0;
    exp9_last_tx = 0;
    exp9_last_rx = 0;
    exp9_have_byte = 0;
}

static void push_exp9_rx_byte(uint8_t val) {
    int i;
    if (exp9_rx_count < (int)(sizeof(exp9_rx_hist) / sizeof(exp9_rx_hist[0]))) {
        exp9_rx_hist[exp9_rx_count++] = val;
    } else {
        for (i = 1; i < (int)(sizeof(exp9_rx_hist) / sizeof(exp9_rx_hist[0])); i++) {
            exp9_rx_hist[i - 1] = exp9_rx_hist[i];
        }
        exp9_rx_hist[(sizeof(exp9_rx_hist) / sizeof(exp9_rx_hist[0])) - 1] = val;
    }
    exp9_last_tx = val;
    exp9_last_rx = val;
    exp9_have_byte = 1;
}

static void push_exp12_history(const char *line0, const char *line1) {
    int i;

    if (exp12_hist_count > 0) {
        if (same_line16(exp12_hist0[exp12_hist_count - 1], line0) &&
            same_line16(exp12_hist1[exp12_hist_count - 1], line1)) {
            return;
        }
    }

    if (exp12_hist_count < 8) {
        copy_line16(exp12_hist0[exp12_hist_count], line0);
        copy_line16(exp12_hist1[exp12_hist_count], line1);
        exp12_hist_count++;
        return;
    }

    for (i = 0; i < 7; i++) {
        copy_line16(exp12_hist0[i], exp12_hist0[i + 1]);
        copy_line16(exp12_hist1[i], exp12_hist1[i + 1]);
    }
    copy_line16(exp12_hist0[7], line0);
    copy_line16(exp12_hist1[7], line1);
}

static int exp12_is_intermediate(uint8_t fsm) {
    switch (fsm) {
        case 0:
        case 1:
        case 2:
        case 4:
        case 5:
        case 7:
        case 9:
        case 10:
            return 1;
        default:
            return 0;
    }
}

static void build_exp12_line0(uint16_t ir, char *buf) {
    uint8_t opcode = (uint8_t)(ir >> 8);
    fill_spaces(buf);

    switch (opcode) {
        case 0x00u: write_text(buf, 0, "ADD"); break;
        case 0x01u: write_text(buf, 0, "STO"); break;
        case 0x02u: write_text(buf, 0, "LOD"); break;
        case 0x03u: write_text(buf, 0, "JMP"); break;
        case 0x04u: write_text(buf, 0, "JNG"); break;
        default:    write_text(buf, 0, "???"); break;
    }

    buf[3] = ' ';
    buf[4] = hex_digit_char((uint8_t)((ir >> 4) & 0x0fu));
    buf[5] = hex_digit_char((uint8_t)(ir & 0x0fu));
}

static void build_exp12_line1(uint8_t fsm, uint16_t ir, uint8_t detail, char *buf) {
    fill_spaces(buf);
    if ((detail == 0u) && exp12_is_intermediate(fsm)) {
        return;
    }

    switch (fsm) {
        case 0u:  write_text(buf, 0, "MAR <= PC"); break;
        case 1u:  write_text(buf, 0, "MDR <= MEM"); break;
        case 2u:  write_text(buf, 0, "IR <= MDR PC++"); break;
        case 3u:  write_text(buf, 0, "DECODE"); break;
        case 4u:
            write_text(buf, 0, "MAR <= ");
            buf[7] = hex_digit_char((uint8_t)((ir >> 4) & 0x0fu));
            buf[8] = hex_digit_char((uint8_t)(ir & 0x0fu));
            break;
        case 5u:  write_text(buf, 0, "MDR <= MEM"); break;
        case 6u:  write_text(buf, 0, "AC <= AC+MDR"); break;
        case 7u:
            write_text(buf, 0, "MAR <= ");
            buf[7] = hex_digit_char((uint8_t)((ir >> 4) & 0x0fu));
            buf[8] = hex_digit_char((uint8_t)(ir & 0x0fu));
            break;
        case 8u:  write_text(buf, 0, "MEM <= AC"); break;
        case 9u:
            write_text(buf, 0, "MAR <= ");
            buf[7] = hex_digit_char((uint8_t)((ir >> 4) & 0x0fu));
            buf[8] = hex_digit_char((uint8_t)(ir & 0x0fu));
            break;
        case 10u: write_text(buf, 0, "MDR <= MEM"); break;
        case 11u: write_text(buf, 0, "AC <= MDR"); break;
        case 12u:
            write_text(buf, 0, "PC <= ");
            buf[6] = hex_digit_char((uint8_t)((ir >> 4) & 0x0fu));
            buf[7] = hex_digit_char((uint8_t)(ir & 0x0fu));
            break;
        case 13u:
            write_text(buf, 0, "AC<0? PC <= ");
            buf[12] = hex_digit_char((uint8_t)((ir >> 4) & 0x0fu));
            buf[13] = hex_digit_char((uint8_t)(ir & 0x0fu));
            break;
        default:
            break;
    }
}

static void write_channel(uint8_t ch) {
#ifdef LOCAL_BUILD
    sim_channel = ch;
    sim_status = ((uint32_t)ch << 4) | ((ch != 0u) ? 1u : 0u);
#else
    EXPDEMO->channel = ch;
#endif
}

static uint8_t read_channel(void) {
#ifdef LOCAL_BUILD
    return (uint8_t)(sim_channel & 0xffu);
#else
    return (uint8_t)(EXPDEMO->channel & 0x0fu);
#endif
}

static uint32_t read_status(void) {
#ifdef LOCAL_BUILD
    return sim_status;
#else
    return EXPDEMO->status;
#endif
}

static void read_monitor(expdemo_monitor_t *m) {
    m->gpio_in = gpio_read_in();
    m->hw_channel = read_channel();
    m->status = read_status();
    m->key_bits = (uint8_t)((m->gpio_in >> 18) & 0x07u);
    m->raw_ir = (uint8_t)((m->gpio_in >> 21) & 0x01u);
    m->dbg_cmd = (uint8_t)((m->gpio_in >> 22) & 0xffu);
    m->dbg_valid = (uint8_t)((m->gpio_in >> 30) & 0x01u);
    m->last_ir = last_ir_cmd;
    m->uptime = board_status_uptime_seconds();
#ifdef LOCAL_BUILD
    m->ir_data = 0;
    m->ir_status = 0;
    m->exp12_snap0 = sim_exp12_snap0;
    m->exp12_ac = sim_exp12_ac;
    m->exp12_ir = sim_exp12_ir;
    m->exp12_step = sim_exp12_step;
    m->exp13_state = sim_exp13_state;
#else
    m->ir_data = IR_DBG->data;
    m->ir_status = IR_DBG->status;
    m->exp12_snap0 = EXPDEMO->exp12_snap0;
    m->exp12_ac = EXPDEMO->exp12_ac;
    m->exp12_ir = EXPDEMO->exp12_ir;
    m->exp12_step = EXPDEMO->exp12_step;
    m->exp13_state = EXPDEMO->exp13_state;
#endif
}

static int monitor_changed(const expdemo_monitor_t *m) {
    if (!have_monitor) {
        return 1;
    }
    return (m->gpio_in != last_monitor.gpio_in) ||
           (m->hw_channel != last_monitor.hw_channel) ||
           (m->status != last_monitor.status) ||
           (m->last_ir != last_monitor.last_ir) ||
           (m->uptime != last_monitor.uptime) ||
           (m->ir_data != last_monitor.ir_data) ||
           (m->ir_status != last_monitor.ir_status) ||
           (m->exp12_snap0 != last_monitor.exp12_snap0) ||
           (m->exp12_ac != last_monitor.exp12_ac) ||
           (m->exp12_ir != last_monitor.exp12_ir) ||
           (m->exp12_step != last_monitor.exp12_step) ||
           (m->exp13_state != last_monitor.exp13_state);
}

static void enter_menu(void) {
    write_channel(0);
    running = 0;
    typed_value = -1;
    dirty = 1;
    have_monitor = 0;
    reset_exp12_history();
    reset_exp9_history();
}

static void exit_demo(void) {
    write_channel(0);
    active = 0;
    running = 0;
    typed_value = -1;
    dirty = 1;
    have_monitor = 0;
    reset_exp12_history();
    reset_exp9_history();
}

static void start_channel(uint8_t ch) {
    selected_channel = ch;
    typed_value = -1;

    if (ch == 0u) {
        enter_menu();
        return;
    }

    if (!valid_channel(ch)) {
        dirty = 1;
        return;
    }

    write_channel(ch);
    running = 1;
    last_hw_channel = -1;
    dirty = 1;
    have_monitor = 0;
    if (ch == 12u) {
        reset_exp12_history();
    }
    if (ch == 9u) {
        reset_exp9_history();
    }
}

static void draw_menu_page(void) {
    int i;

    vga_puts("expdemo Home\n", VGA_CYAN);
    vga_puts("============\n", VGA_WHITE);
    vga_puts("Unified pure-VHDL course experiments.\n", VGA_GREEN);
    vga_puts("Pick a channel, then enter its instruction + live-monitor page.\n", VGA_GRAY);
    vga_puts("KEY0 is always reserved for board reset.\n", VGA_RED);
    vga_puts("Menu: digits+Enter start  BS delete  +/- browse  q exit shell\n", VGA_GRAY);
    vga_puts("IR: digits input  CH+/CH- browse  RETURN/PLAY start  MENU exit shell\n\n", VGA_GRAY);

    vga_puts("Selected: ", VGA_WHITE);
    if (typed_value >= 0) {
        put_dec_u8((uint8_t)typed_value, VGA_YELLOW);
    } else {
        put_dec_u8(selected_channel, VGA_YELLOW);
    }

    {
        const exp_entry_t *entry = find_entry((typed_value >= 0) ? (uint8_t)typed_value : selected_channel);
        if (entry) {
            vga_puts("  ", VGA_WHITE);
            vga_puts(entry->name, VGA_GREEN);
            vga_puts(" - ", VGA_WHITE);
            vga_puts(entry->detail, VGA_GREEN);
        } else if ((typed_value == 8) || (typed_value == 10)) {
            vga_puts("  redirected to shell command ", VGA_WHITE);
            vga_puts((typed_value == 8) ? "ps2" : "info", VGA_GREEN);
        } else if ((typed_value >= 0) && !valid_channel((uint8_t)typed_value)) {
            vga_puts("  invalid/reserved", VGA_RED);
        }
        vga_puts("\n\n", VGA_BLACK);
    }

    vga_puts("Available Experiments\n", VGA_CYAN);
    vga_puts("---------------------\n", VGA_WHITE);
    for (i = 0; i < exp_count(); i++) {
        const exp_entry_t *entry = &exp_entries[i];
        vga_puts("  ", VGA_WHITE);
        put_dec_u8(entry->id, VGA_YELLOW);
        vga_puts("  ", VGA_WHITE);
        vga_puts(entry->name, VGA_GREEN);
        vga_puts("  ", VGA_WHITE);
        vga_puts(entry->detail, VGA_GRAY);
        vga_puts("\n", VGA_BLACK);
    }
    vga_puts("\nUse shell command ", VGA_WHITE);
    vga_puts("ps2", VGA_GREEN);
    vga_puts(" for former Exp8 keyboard scan-code demo.\n", VGA_GRAY);
    vga_puts("Use shell command ", VGA_WHITE);
    vga_puts("info", VGA_GREEN);
    vga_puts(" for former Exp10 IR/system live monitor.\n", VGA_GRAY);
    vga_puts("Reserved channels: 6, 7\n", VGA_RED);
}

static void draw_exp12_page(const exp_entry_t *entry, const expdemo_monitor_t *mon) {
    uint8_t pc = (uint8_t)(mon->exp12_snap0 & 0xffu);
    uint8_t fsm = (uint8_t)((mon->exp12_snap0 >> 8) & 0x0fu);
    uint8_t auto_run = (uint8_t)((mon->exp12_snap0 >> 12) & 0x01u);
    uint8_t detail = (uint8_t)((mon->exp12_snap0 >> 13) & 0x01u);
    uint16_t ac = (uint16_t)(mon->exp12_ac & 0xffffu);
    uint16_t ir = (uint16_t)(mon->exp12_ir & 0xffffu);
    uint8_t step = (uint8_t)(mon->exp12_step & 0xffu);
    char line0[17];
    char line1[17];

    build_exp12_line0(ir, line0);
    build_exp12_line1(fsm, ir, detail, line1);
    push_exp12_history(line0, line1);

    vga_puts("expdemo - ", VGA_CYAN);
    vga_puts(entry->name, VGA_CYAN);
    vga_puts("\n", VGA_WHITE);
    vga_puts("====================\n", VGA_WHITE);
    vga_puts(entry->detail, VGA_GREEN);
    vga_puts("\n", VGA_BLACK);
    vga_puts("SW : ", VGA_WHITE);
    vga_puts(entry->sw_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("KEY: ", VGA_WHITE);
    vga_puts(entry->key_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("I/O: ", VGA_WHITE);
    vga_puts(entry->io_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("Exit: q/MENU -> home, digits+Enter -> switch experiment\n", VGA_GRAY);

    vga_puts("CPU Snapshot\n", VGA_CYAN);
    vga_puts("------------\n", VGA_WHITE);
    vga_puts("PC=0x", VGA_WHITE);
    put_hex8(pc, VGA_YELLOW);
    vga_puts("  AC=0x", VGA_WHITE);
    put_hex16(ac, VGA_CYAN);
    vga_puts("  IR=0x", VGA_WHITE);
    put_hex16(ir, VGA_CYAN);
    vga_puts("\n", VGA_BLACK);
    vga_puts("FSM=0x", VGA_WHITE);
    put_hex8(fsm, VGA_YELLOW);
    vga_puts("  Mode=", VGA_WHITE);
    vga_puts(auto_run ? "AUTO" : "STEP", auto_run ? VGA_GREEN : VGA_YELLOW);
    vga_puts("  Detail=", VGA_WHITE);
    vga_puts(detail ? "FULL" : "BRIEF", detail ? VGA_GREEN : VGA_YELLOW);
    vga_puts("  Steps=0x", VGA_WHITE);
    put_hex8(step, VGA_CYAN);
    vga_puts("\n\n", VGA_BLACK);

    vga_puts("LCD Trace (latest 8)\n", VGA_CYAN);
    vga_puts("--------------------\n", VGA_WHITE);
    {
        int i;
        for (i = 0; i < 8; i++) {
            vga_putc('[', VGA_WHITE);
            vga_puts(exp12_hist0[i], VGA_YELLOW);
            vga_puts("]    [", VGA_WHITE);
            vga_puts(exp12_hist1[i], VGA_GREEN);
            vga_puts("]\n", VGA_WHITE);
        }
    }
}

static void build_exp13_window_line(const char *src, uint8_t offset, char *buf) {
    int i;
    fill_spaces(buf);
    for (i = 0; i < 16; i++) {
        char c = src[offset + i];
        if (c == '\0') {
            break;
        }
        buf[i] = c;
    }
}

static void build_exp13_lines(const expdemo_monitor_t *mon, char *line0, char *line1, uint8_t *page_o, uint8_t *scroll_o) {
    static const char msg0_line0[] = "DE2-115 LCD     ";
    static const char msg0_line1[] = "Hello FPGA !    ";
    static const char msg1_line0[] = "DE2-115 LCD     ";
    static const char msg1_line1[] = "DE2-115 Board   ";
    static const char msg2_line0[] = "Scrolling demo message on DE2-115 LCD board                        ";
    static const char msg2_line1[] = "Cyclone IV FPGA shows scrolling ability!                        ";
    uint8_t page = (uint8_t)(mon->exp13_state & 0x03u);
    uint8_t scroll = (uint8_t)((mon->exp13_state >> 2) & 0x3fu);
    uint8_t sw = (uint8_t)(mon->gpio_in & 0xffu);

    fill_spaces(line0);
    fill_spaces(line1);
    *page_o = page;
    *scroll_o = scroll;

    switch (page) {
        case 0u:
            copy_line16(line0, msg0_line0);
            copy_line16(line1, msg0_line1);
            break;
        case 1u:
            copy_line16(line0, msg1_line0);
            copy_line16(line1, msg1_line1);
            break;
        case 2u:
            build_exp13_window_line(msg2_line0, scroll, line0);
            build_exp13_window_line(msg2_line1, scroll, line1);
            break;
        case 3u:
            write_text(line0, 0, "SW=0x");
            line0[5] = hex_digit_char((uint8_t)(sw >> 4));
            line0[6] = hex_digit_char(sw);
            write_text(line1, 0, "BIN:");
            line1[4] = (sw & 0x80u) ? '1' : '0';
            line1[5] = (sw & 0x40u) ? '1' : '0';
            line1[6] = (sw & 0x20u) ? '1' : '0';
            line1[7] = (sw & 0x10u) ? '1' : '0';
            line1[8] = (sw & 0x08u) ? '1' : '0';
            line1[9] = (sw & 0x04u) ? '1' : '0';
            line1[10] = (sw & 0x02u) ? '1' : '0';
            line1[11] = (sw & 0x01u) ? '1' : '0';
            break;
        default:
            break;
    }
}

static void draw_exp13_page(const exp_entry_t *entry, const expdemo_monitor_t *mon) {
    char line0[17];
    char line1[17];
    uint8_t page;
    uint8_t scroll;

    build_exp13_lines(mon, line0, line1, &page, &scroll);

    vga_puts("expdemo - ", VGA_CYAN);
    vga_puts(entry->name, VGA_CYAN);
    vga_puts("\n", VGA_WHITE);
    vga_puts("====================\n", VGA_WHITE);
    vga_puts(entry->detail, VGA_GREEN);
    vga_puts("\n", VGA_BLACK);
    vga_puts("SW : ", VGA_WHITE);
    vga_puts(entry->sw_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("KEY: ", VGA_WHITE);
    vga_puts(entry->key_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("I/O: ", VGA_WHITE);
    vga_puts(entry->io_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("Exit: q/MENU -> home, digits+Enter -> switch experiment\n\n", VGA_GRAY);

    vga_puts("LCD Layout\n", VGA_CYAN);
    vga_puts("----------\n", VGA_WHITE);
    vga_puts("+----------------+\n", VGA_WHITE);
    vga_puts("|", VGA_WHITE);
    vga_puts(line0, VGA_YELLOW);
    vga_puts("|\n", VGA_WHITE);
    vga_puts("|", VGA_WHITE);
    vga_puts(line1, VGA_GREEN);
    vga_puts("|\n", VGA_WHITE);
    vga_puts("+----------------+\n", VGA_WHITE);
    vga_puts("Page=", VGA_WHITE);
    put_dec_u8((uint8_t)(page + 1u), VGA_YELLOW);
    if (page == 2u) {
        vga_puts("  Scroll=", VGA_WHITE);
        put_dec_u8(scroll, VGA_CYAN);
    }
    vga_puts("\n", VGA_BLACK);
}

static uint64_t exp11_freq_millihz(uint8_t mode, uint8_t fword) {
    uint64_t clk_hz;
    uint64_t phase_step;

    if (mode == 0u) {
        clk_hz = 100000u;
        phase_step = (uint64_t)fword;
    } else {
        clk_hz = 50000000u;
        phase_step = (uint64_t)fword << 8;
    }

    return ((clk_hz * phase_step * 1000u) + (1u << 19)) >> 20;
}

static void put_freq_millihz(uint64_t mhz, uint16_t color) {
    uint32_t hz_int = (uint32_t)(mhz / 1000u);
    uint32_t hz_frac = (uint32_t)(mhz % 1000u);

    put_dec_u32(hz_int, color);
    vga_putc('.', color);
    vga_putc((char)('0' + ((hz_frac / 100u) % 10u)), color);
    vga_putc((char)('0' + ((hz_frac / 10u) % 10u)), color);
    vga_putc((char)('0' + (hz_frac % 10u)), color);
    vga_puts(" Hz", color);
}

static void draw_exp11_page(const exp_entry_t *entry, const expdemo_monitor_t *mon) {
    uint8_t sw_mode = (uint8_t)((mon->gpio_in >> 17) & 0x01u);
    uint8_t fword = (uint8_t)(mon->gpio_in & 0xffu);
    uint64_t freq_mhz = exp11_freq_millihz(sw_mode, fword);

    vga_puts("expdemo - ", VGA_CYAN);
    vga_puts(entry->name, VGA_CYAN);
    vga_puts("\n", VGA_WHITE);
    vga_puts("====================\n", VGA_WHITE);
    vga_puts(entry->detail, VGA_GREEN);
    vga_puts("\n", VGA_BLACK);
    vga_puts("SW : ", VGA_WHITE);
    vga_puts(entry->sw_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("KEY: ", VGA_WHITE);
    vga_puts(entry->key_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("I/O: ", VGA_WHITE);
    vga_puts(entry->io_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("Exit: q/MENU -> home, digits+Enter -> switch experiment\n\n", VGA_GRAY);

    vga_puts("Sine DDS Status\n", VGA_CYAN);
    vga_puts("---------------\n", VGA_WHITE);
    vga_puts("SW17 mode  : ", VGA_WHITE);
    if (sw_mode == 0u) {
        vga_puts("0  LED observe / slow clock", VGA_YELLOW);
    } else {
        vga_puts("1  SignalTap capture / fast clock", VGA_YELLOW);
    }
    vga_puts("\n", VGA_BLACK);

    vga_puts("SW7:0 fword: 0x", VGA_WHITE);
    put_hex8(fword, VGA_CYAN);
    vga_puts("  (", VGA_WHITE);
    put_dec_u8(fword, VGA_YELLOW);
    vga_puts(")\n", VGA_WHITE);

    vga_puts("Estimated f0: ", VGA_WHITE);
    put_freq_millihz(freq_mhz, VGA_GREEN);
    vga_puts("\n", VGA_BLACK);

    vga_puts("Formula     : ", VGA_WHITE);
    if (sw_mode == 0u) {
        vga_puts("100 kHz * fword / 2^20", VGA_GRAY);
    } else {
        vga_puts("50 MHz * (fword << 8) / 2^20", VGA_GRAY);
    }
    vga_puts("\n\n", VGA_BLACK);

    vga_puts("Live Inputs\n", VGA_CYAN);
    vga_puts("-----------\n", VGA_WHITE);
    vga_puts("SW[17:0]   : ", VGA_WHITE);
    put_bits(mon->gpio_in & 0x3ffffu, 18, VGA_YELLOW);
    vga_puts("\n", VGA_BLACK);
    vga_puts("KEY[3:1]   : ", VGA_WHITE);
    put_bits(mon->key_bits, 3, VGA_YELLOW);
    vga_puts("  (KEY0 = board reset)\n", VGA_GRAY);
}

static char ascii_cell(uint8_t val) {
    if (val >= 32u && val <= 126u) {
        return (char)val;
    }
    return '.';
}

static void draw_exp9_rx_box(void) {
    int i;
    int start = 0;

    if (exp9_rx_count > 8) {
        start = exp9_rx_count - 8;
    }

    vga_puts("RX History\n", VGA_CYAN);
    vga_puts("----------\n", VGA_WHITE);
    vga_puts("+--------------------------------------+\n", VGA_WHITE);
    vga_puts("| HEX : ", VGA_WHITE);
    if (exp9_rx_count == 0) {
        vga_puts("--", VGA_GRAY);
    } else {
        for (i = start; i < exp9_rx_count; i++) {
            if (i != start) {
                vga_putc(' ', VGA_WHITE);
            }
            put_hex8(exp9_rx_hist[i], VGA_YELLOW);
        }
    }
    vga_puts(" |\n", VGA_WHITE);

    vga_puts("| ASCII: ", VGA_WHITE);
    if (exp9_rx_count == 0) {
        vga_puts("(empty)", VGA_GRAY);
    } else {
        for (i = start; i < exp9_rx_count; i++) {
            vga_putc(ascii_cell(exp9_rx_hist[i]), VGA_GREEN);
        }
    }
    vga_puts(" |\n", VGA_WHITE);
    vga_puts("+--------------------------------------+\n", VGA_WHITE);
}

static void draw_exp9_page(const exp_entry_t *entry, const expdemo_monitor_t *mon) {
    uint8_t sw_byte = (uint8_t)(mon->gpio_in & 0xffu);

    vga_puts("expdemo - ", VGA_CYAN);
    vga_puts(entry->name, VGA_CYAN);
    vga_puts("\n", VGA_WHITE);
    vga_puts("====================\n", VGA_WHITE);
    vga_puts(entry->detail, VGA_GREEN);
    vga_puts("\n", VGA_BLACK);
    vga_puts("SW : ", VGA_WHITE);
    vga_puts(entry->sw_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("KEY: ", VGA_WHITE);
    vga_puts(entry->key_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("I/O: ", VGA_WHITE);
    vga_puts(entry->io_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("Exit: q/MENU -> home, digits+Enter -> switch experiment\n\n", VGA_GRAY);

    vga_puts("Virtual UART\n", VGA_CYAN);
    vga_puts("------------\n", VGA_WHITE);
    vga_puts("TX is looped back into RX inside Exp9.\n", VGA_GRAY);
    vga_puts("Set SW[7:0], then press KEY1 to send.\n", VGA_GRAY);
    vga_puts("TX > send 0x", VGA_WHITE);
    put_hex8(sw_byte, VGA_YELLOW);
    vga_puts("  ASCII '", VGA_WHITE);
    vga_putc(ascii_cell(sw_byte), VGA_GREEN);
    vga_puts("'  via KEY1\n", VGA_WHITE);
    vga_puts("Last loopback : ", VGA_WHITE);
    if (exp9_have_byte) {
        vga_puts("TX=0x", VGA_WHITE);
        put_hex8(exp9_last_tx, VGA_YELLOW);
        vga_puts("  RX=0x", VGA_WHITE);
        put_hex8(exp9_last_rx, VGA_GREEN);
        vga_puts("  ASCII '", VGA_WHITE);
        vga_putc(ascii_cell(exp9_last_rx), VGA_GREEN);
        vga_puts("'\n", VGA_WHITE);
    } else {
        vga_puts("-- (press KEY1 to send)\n", VGA_GRAY);
    }
    draw_exp9_rx_box();

    vga_puts("Live Inputs\n", VGA_CYAN);
    vga_puts("-----------\n", VGA_WHITE);
    vga_puts("SW[7:0]    : ", VGA_WHITE);
    put_bits(sw_byte, 8, VGA_YELLOW);
    vga_puts("\n", VGA_BLACK);
    vga_puts("KEY[3:1]   : ", VGA_WHITE);
    put_bits(mon->key_bits, 3, VGA_YELLOW);
    vga_puts("  (KEY0 = board reset)\n", VGA_GRAY);
}

static void draw_active_page(void) {
    expdemo_monitor_t mon;
    const exp_entry_t *entry;

    read_monitor(&mon);
    last_monitor = mon;
    have_monitor = 1;
    entry = find_entry(mon.hw_channel);

    if (!entry) {
        vga_puts("expdemo\n", VGA_CYAN);
        vga_puts("No valid experiment selected.\n", VGA_RED);
        return;
    }

    if (mon.hw_channel == 12u) {
        draw_exp12_page(entry, &mon);
        return;
    }
    if (mon.hw_channel == 11u) {
        draw_exp11_page(entry, &mon);
        return;
    }
    if (mon.hw_channel == 9u) {
        draw_exp9_page(entry, &mon);
        return;
    }
    if (mon.hw_channel == 13u) {
        draw_exp13_page(entry, &mon);
        return;
    }

    vga_puts("expdemo - ", VGA_CYAN);
    vga_puts(entry->name, VGA_CYAN);
    vga_puts("\n", VGA_WHITE);
    vga_puts("====================\n", VGA_WHITE);
    vga_puts(entry->detail, VGA_GREEN);
    vga_puts("\n", VGA_BLACK);
    vga_puts("SW : ", VGA_WHITE);
    vga_puts(entry->sw_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("KEY: ", VGA_WHITE);
    vga_puts(entry->key_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("I/O: ", VGA_WHITE);
    vga_puts(entry->io_desc, VGA_GRAY);
    vga_puts("\n", VGA_BLACK);
    vga_puts("Exit: q/MENU -> home, digits+Enter -> switch experiment\n\n", VGA_GRAY);

    vga_puts("Live Monitor\n", VGA_CYAN);
    vga_puts("------------\n", VGA_WHITE);

    vga_puts("HW channel : ", VGA_WHITE);
    put_dec_u8(mon.hw_channel, VGA_YELLOW);
    vga_puts("  STATUS=0x", VGA_WHITE);
    put_hex32(mon.status, VGA_CYAN);
    vga_puts("\n", VGA_BLACK);

    vga_puts("SW[17:0]   : ", VGA_WHITE);
    put_bits(mon.gpio_in & 0x3ffffu, 18, VGA_YELLOW);
    vga_puts("\n", VGA_BLACK);

    vga_puts("KEY[3:1]   : ", VGA_WHITE);
    put_bits(mon.key_bits, 3, VGA_YELLOW);
    vga_puts("  (KEY0 = board reset)\n", VGA_GRAY);

    vga_puts("Last IR    : ", VGA_WHITE);
    if (mon.last_ir != 0u || mon.dbg_valid != 0u) {
        put_hex8(mon.last_ir, VGA_YELLOW);
        vga_puts("  ", VGA_WHITE);
        vga_puts(ir_label(mon.last_ir), VGA_GREEN);
    } else {
        vga_puts("-- (none)", VGA_GRAY);
    }
    vga_puts("\n", VGA_BLACK);

    vga_puts("IR RAW     : ", VGA_WHITE);
    vga_putc(mon.raw_ir ? '1' : '0', mon.raw_ir ? VGA_GREEN : VGA_YELLOW);
    vga_puts("  DBG V/CMD: ", VGA_WHITE);
    vga_putc(mon.dbg_valid ? '1' : '0', mon.dbg_valid ? VGA_GREEN : VGA_YELLOW);
    vga_puts(" / 0x", VGA_WHITE);
    put_hex8(mon.dbg_cmd, VGA_CYAN);
    vga_puts("\n", VGA_BLACK);

    vga_puts("IR REG     : DATA=0x", VGA_WHITE);
    put_hex32(mon.ir_data, VGA_CYAN);
    vga_puts("  ST=0x", VGA_WHITE);
    put_hex32(mon.ir_status, VGA_CYAN);
    vga_puts("\n", VGA_BLACK);

    vga_puts("Uptime     : 0x", VGA_WHITE);
    put_hex32(mon.uptime, VGA_CYAN);
    vga_puts(" s\n", VGA_GREEN);
}

static void redraw(void) {
    vga_clear();
    vga_goto(0, 0);
    if (running) {
        draw_active_page();
    } else {
        draw_menu_page();
    }
    dirty = 0;
}

static void accept_digit(uint8_t digit) {
    if (typed_value < 0) {
        typed_value = digit;
    } else {
        int next = typed_value * 10 + digit;
        if (next <= 13) {
            typed_value = next;
        } else {
            typed_value = digit;
        }
    }
    dirty = 1;
}

static void accept_enter(void) {
    uint8_t ch;

    if (typed_value >= 0) {
        ch = (uint8_t)typed_value;
    } else {
        ch = selected_channel;
    }

    if (!valid_channel(ch)) {
        dirty = 1;
        return;
    }

    start_channel(ch);
}

static void init(void) {
    active = 1;
    running = 0;
    dirty = 1;
    typed_value = -1;
    last_hw_channel = -1;
    selected_channel = 1;
    have_monitor = 0;
    write_channel(0);
    redraw();
}

static void update(void) {
    int hw_channel;
    expdemo_monitor_t mon;

    if (!active) {
        return;
    }

    hw_channel = (int)read_channel();

    if (running && (hw_channel == 0)) {
        running = 0;
        dirty = 1;
        have_monitor = 0;
    } else if (running) {
        if (hw_channel != last_hw_channel) {
            last_hw_channel = hw_channel;
            selected_channel = (uint8_t)hw_channel;
            dirty = 1;
            have_monitor = 0;
        }

        read_monitor(&mon);
        if ((hw_channel == 9) && have_monitor &&
            ((last_monitor.key_bits & 0x01u) == 0u) &&
            ((mon.key_bits & 0x01u) != 0u)) {
            push_exp9_rx_byte((uint8_t)(mon.gpio_in & 0xffu));
            dirty = 1;
        }
        if ((hw_channel == 12) && have_monitor &&
            ((last_monitor.key_bits & 0x01u) == 0u) &&
            ((mon.key_bits & 0x01u) != 0u)) {
            reset_exp12_history();
        }
        if (monitor_changed(&mon)) {
            dirty = 1;
        }
    }

    if (dirty) {
        redraw();
    }
}

static void input(char c) {
    if (c == 'q' || c == 'Q' || c == 27) {
        if (running) {
            enter_menu();
        } else {
            exit_demo();
        }
        return;
    }

    if (c == '\b' || c == 0x7fu) {
        if (typed_value >= 10) {
            typed_value /= 10;
        } else {
            typed_value = -1;
        }
        dirty = 1;
        return;
    }

    if (c == '+' || c == '=') {
        selected_channel = next_channel(selected_channel);
        typed_value = -1;
        dirty = 1;
        return;
    }

    if (c == '-') {
        selected_channel = prev_channel(selected_channel);
        typed_value = -1;
        dirty = 1;
        return;
    }

    if (c == '\r' || c == '\n') {
        accept_enter();
        return;
    }

    if (c >= '0' && c <= '9') {
        accept_digit((uint8_t)(c - '0'));
    }
}

static void ir_input(uint8_t cmd) {
    switch (cmd) {
        case IR_BTN_MENU:
            if (running) {
                enter_menu();
            } else {
                exit_demo();
            }
            return;
        case IR_BTN_RETURN:
        case IR_BTN_PLAY:
            accept_enter();
            return;
        case IR_BTN_CH_UP:
            selected_channel = next_channel(selected_channel);
            typed_value = -1;
            dirty = 1;
            return;
        case IR_BTN_CH_DN:
            selected_channel = prev_channel(selected_channel);
            typed_value = -1;
            dirty = 1;
            return;
        case IR_BTN_0: accept_digit(0); return;
        case IR_BTN_1: accept_digit(1); return;
        case IR_BTN_2: accept_digit(2); return;
        case IR_BTN_3: accept_digit(3); return;
        case IR_BTN_4: accept_digit(4); return;
        case IR_BTN_5: accept_digit(5); return;
        case IR_BTN_6: accept_digit(6); return;
        case IR_BTN_7: accept_digit(7); return;
        case IR_BTN_8: accept_digit(8); return;
        case IR_BTN_9: accept_digit(9); return;
        case IR_BTN_A:
            selected_channel = 1;
            typed_value = -1;
            dirty = 1;
            return;
        default:
            return;
    }
}

static int finish(void) {
    return !active;
}

const program_t prog_demo = {
    "expdemo", "Unified VHDL experiment entry",
    init, update, input, ir_input, finish
};
