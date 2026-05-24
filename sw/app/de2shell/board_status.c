#include "board_status.h"
#include "gpio_hal.h"
#include "lcd_hal.h"

#ifdef LOCAL_BUILD
  #include <time.h>
#else
  #include <neorv32.h>
#endif

#ifdef LOCAL_BUILD
  static time_t uptime_start;
#endif

static uint32_t current_word;
static int claimed;
static char lcd_line1_cache[16];
static char lcd_line2_cache[16];
static int lcd_cache_valid;

static char hex_digit(unsigned value) {
    value &= 0x0fu;
    return (value < 10u) ? (char)('0' + value) : (char)('A' + (value - 10u));
}

static void fill_spaces(char *buf) {
    for (int i = 0; i < 16; i++) {
        buf[i] = ' ';
    }
}

static void write_text(char *buf, int pos, const char *text) {
    int i = 0;

    while ((pos + i) < 16 && text[i] != '\0') {
        buf[pos + i] = text[i];
        i++;
    }
}

static int lcd_lines_same(const char *line1, const char *line2) {
    if (!lcd_cache_valid) {
        return 0;
    }
    for (int i = 0; i < 16; i++) {
        if (lcd_line1_cache[i] != line1[i] || lcd_line2_cache[i] != line2[i]) {
            return 0;
        }
    }
    return 1;
}

static void lcd_cache_store(const char *line1, const char *line2) {
    for (int i = 0; i < 16; i++) {
        lcd_line1_cache[i] = line1[i];
        lcd_line2_cache[i] = line2[i];
    }
    lcd_cache_valid = 1;
}

static void lcd_commit_lines(const char *line1, const char *line2) {
    if (lcd_lines_same(line1, line2)) {
        return;
    }
    lcd_write_lines(line1, line2);
    lcd_cache_store(line1, line2);
}

static const char *program_title(uint8_t prog_id) {
    switch (prog_id & 0x0fu) {
        case 1u: return "DE2Extra Hello";
        case 2u: return "DE2Extra SDRAM";
        case 3u: return "DE2Extra Crypto";
        case 4u: return "DE2Extra PS/2";
        case 5u: return "DE2Extra Snake";
        case 6u: return "DE2Extra Life";
        case 7u: return "DE2Extra Info";
        case 8u: return "DE2Extra Info";
        case 9u: return "DE2Extra Asm";
        case 10u: return "DE2Extra Demo";
        default: return "DE2Extra Shell";
    }
}

static const char *program_abbr(uint8_t prog_id) {
    switch (prog_id & 0x0fu) {
        case 1u: return "HELO";
        case 2u: return "SDRM";
        case 3u: return "CRYP";
        case 4u: return "PS2 ";
        case 5u: return "SNAK";
        case 6u: return "LIFE";
        case 7u: return "INFO";
        case 8u: return "INFO";
        case 9u: return "MONI";
        case 10u: return "DEMO";
        default: return "SHEL";
    }
}

static const char *state_text(uint8_t state) {
    switch (state & 0x0fu) {
        case BOARD_STATE_LIVE: return "LIVE";
        case BOARD_STATE_RUN:  return "RUN";
        case BOARD_STATE_EDIT: return "EDIT";
        case BOARD_STATE_HOLD: return "HOLD";
        case BOARD_STATE_PASS: return "PASS";
        case BOARD_STATE_FAIL: return "FAIL";
        case BOARD_STATE_BUSY: return "BUSY";
        default: return "READY";
    }
}

static void lcd_render_program(uint8_t prog_id, uint8_t state) {
    char line1[16];
    char line2[16];

    fill_spaces(line1);
    fill_spaces(line2);
    write_text(line1, 0, program_title(prog_id));

    line2[0] = 'C';
    line2[1] = 'H';
    line2[2] = hex_digit(prog_id);
    line2[3] = ' ';
    write_text(line2, 4, program_abbr(prog_id));
    line2[8] = ' ';
    write_text(line2, 9, state_text(state));

    lcd_commit_lines(line1, line2);
}

static void lcd_render_word(uint32_t word) {
    char line1[16];
    char line2[16];

    fill_spaces(line1);
    fill_spaces(line2);
    write_text(line1, 0, "DE2Extra Status");
    write_text(line2, 0, "RAW ");
    for (int i = 0; i < 8; i++) {
        line2[4 + i] = hex_digit((unsigned)(word >> ((7 - i) * 4)));
    }
    lcd_commit_lines(line1, line2);
}

static uint32_t compose_program_word(uint8_t prog_id, uint8_t state, uint8_t flags, uint16_t data) {
    uint32_t word = 0x40000000u;
    word |= ((uint32_t)(prog_id & 0x0fu)) << 24;
    word |= ((uint32_t)(state & 0x0fu)) << 20;
    word |= ((uint32_t)(flags & 0x0fu)) << 16;
    word |= (uint32_t)data;
    return word;
}

void board_status_init(void) {
    claimed = 0;
    current_word = 0xffffffffu;
    lcd_cache_valid = 0;
#ifdef LOCAL_BUILD
    uptime_start = time(NULL);
#endif
    lcd_init();
    lcd_render_program(0u, BOARD_STATE_READY);
}

void board_status_release(void) {
    claimed = 0;
}

int board_status_claimed(void) {
    return claimed;
}

void board_status_set_program(uint8_t prog_id, uint8_t state, uint8_t flags, uint16_t data) {
    uint32_t word = compose_program_word(prog_id, state, flags, data);

    claimed = 1;
    if (word != current_word) {
        current_word = word;
        gpio_write_out(word);
    }
    lcd_render_program(prog_id, state);
}

void board_status_set_word(uint32_t word) {
    claimed = 1;
    if (word != current_word) {
        current_word = word;
        gpio_write_out(word);
    }
    lcd_render_word(word);
}

void board_status_apply_fallback(uint8_t prog_id, uint8_t state) {
    uint32_t word;

    if (claimed) {
        return;
    }

    word = gpio_read_out();
    word &= 0x000fffffu;
    word |= 0x40000000u;
    word |= ((uint32_t)(prog_id & 0x0fu)) << 24;
    word |= ((uint32_t)(state & 0x0fu)) << 20;
    if (word != current_word) {
        current_word = word;
        gpio_write_out(word);
    }
    lcd_render_program(prog_id, state);
}

uint32_t board_status_uptime_seconds(void) {
#ifdef LOCAL_BUILD
    time_t now = time(NULL);
    if (now <= uptime_start) {
        return 0;
    }
    return (uint32_t)(now - uptime_start);
#else
    if (neorv32_clint_available() == 0) {
        return 0;
    }
    return (uint32_t)(neorv32_clint_time_get() / (uint64_t)neorv32_sysinfo_get_clk());
#endif
}
