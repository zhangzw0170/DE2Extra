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

/* ── Line 1: "DE2Ex XX ABBBBB " ─────────────────────────────────── */

static const char *program_abbr(uint8_t prog_id) {
    switch (prog_id & 0x0fu) {
        case  0u: return "SHELL ";
        case  1u: return "HELLO ";
        case  2u: return "CRYPTO";
        case  3u: return "KBD   ";
        case  4u: return "SNAKE ";
        case  5u: return "INFO  ";
        case  6u: return "RISCV ";
        case  7u: return "EXP   ";
        case  8u: return "TWM   ";
        case  9u: return "CONWAY";
        case 10u: return "NTT   ";
        case 11u: return "SYNTH ";
        case 12u: return "PFORTH";
        default:  return "UNK   ";
    }
}

static void build_line1(char *buf, uint8_t prog_id) {
    const char *abbr = program_abbr(prog_id);
    buf[0]  = 'D';
    buf[1]  = 'E';
    buf[2]  = '2';
    buf[3]  = 'E';
    buf[4]  = 'x';
    buf[5]  = ' ';
    buf[6]  = (char)('0' + (prog_id / 10u));
    buf[7]  = (char)('0' + (prog_id % 10u));
    buf[8]  = ' ';
    for (int i = 0; i < 6; i++) {
        buf[9 + i] = abbr[i];
    }
    buf[15] = ' ';
}

/* ── Line 2: per-program specialized ─────────────────────────────── */

static void render_progress_bar(char *buf, const char *label, uint8_t pct) {
    fill_spaces(buf);
    write_text(buf, 0, label);
    buf[4] = '[';
    /* bar width = 6, positions 5-10 */
    {
        int filled = (int)((unsigned)pct * 6u / 100u);
        if (filled > 6) filled = 6;
        for (int i = 0; i < 6; i++) {
            buf[5 + i] = (i < filled) ? '=' : ' ';
        }
    }
    buf[11] = ']';
    if (pct >= 100u) {
        buf[13] = '1';
        buf[14] = '0';
        buf[15] = '0';
    } else if (pct >= 10u) {
        buf[13] = (char)('0' + pct / 10u);
        buf[14] = (char)('0' + pct % 10u);
        buf[15] = '%';
    } else {
        buf[13] = (char)('0' + pct);
        buf[14] = '%';
    }
}

static void render_line2(char *buf, uint8_t prog_id, uint8_t state,
                         uint8_t flags, uint16_t data) {
    fill_spaces(buf);

    switch (prog_id & 0x0fu) {
    case 0u: /* SHELL */
        write_text(buf, 0, "READY");
        break;

    case 1u: /* HELLO */
        write_text(buf, 0, "RUNNING");
        break;

    case 2u: /* CRYPTO: progress bar via flags=sub_id, data=progress% */
        {
            static const char *crypto_labels[] = {
                "AES", "AES", "SHA", "SM4"
            };
            const char *label = (flags < 4u) ? crypto_labels[flags] : "RUN";
            render_progress_bar(buf, label, (uint8_t)(data & 0xFFu));
        }
        break;

    case 3u: /* KBD: data = ascii(8) | lock_flags(8) */
        {
            uint8_t ascii = (uint8_t)(data >> 8u);
            uint8_t locks = (uint8_t)(data & 0xFFu);
            if (ascii >= 0x20u && ascii < 0x7Fu) {
                buf[0] = '\'';
                buf[1] = (char)ascii;
                buf[2] = '\'';
            } else if (ascii != 0u) {
                buf[0] = '0';
                buf[1] = 'x';
                buf[2] = hex_digit((unsigned)(ascii >> 4u));
                buf[3] = hex_digit((unsigned)ascii);
            }
            /* lock indicators at pos 13,14,15 */
            buf[13] = (locks & 0x04u) ? 'N' : '-';
            buf[14] = (locks & 0x02u) ? 'C' : '-';
            buf[15] = (locks & 0x01u) ? 'S' : '-';
        }
        break;

    case 4u: /* SNAKE: data = speed_level */
        write_text(buf, 0, "SPEED:");
        {
            unsigned spd = data & 0xFFu;
            if (spd >= 10u) {
                buf[7] = (char)('0' + spd / 10u);
                buf[8] = (char)('0' + spd % 10u);
            } else {
                buf[7] = (char)('0' + spd);
            }
        }
        break;

    case 5u: /* INFO: SW build time from flags/data */
        write_text(buf, 0, "SW ");
        {
            /* flags=month, data=day*256+hm encoded by caller */
            unsigned mo = flags & 0x0Fu;
            unsigned dd = (data >> 8u) & 0x1Fu;
            unsigned hh = (data >> 3u) & 0x1Fu;
            unsigned mm = data & 0x07u;
            buf[3] = (char)('0' + mo / 10u);
            buf[4] = (char)('0' + mo % 10u);
            buf[5] = '/';
            buf[6] = (char)('0' + dd / 10u);
            buf[7] = (char)('0' + dd % 10u);
            buf[8] = ' ';
            buf[9] = (char)('0' + hh / 10u);
            buf[10] = (char)('0' + hh % 10u);
            buf[11] = ':';
            buf[12] = (char)('0' + mm);
            /* mm only has 3 bits; fallback */
        }
        break;

    case 6u: /* RISCV: data = pc_lo(16) */
        write_text(buf, 0, "PC:");
        for (int i = 0; i < 4; i++) {
            buf[3 + i] = hex_digit((unsigned)(data >> (12 - i * 4)));
        }
        break;

    case 7u: /* EXP: data = exp_id(8) */
        {
            uint8_t eid = (uint8_t)(data & 0xFFu);
            buf[0] = 'E';
            if (eid >= 10u) {
                buf[1] = (char)('0' + eid / 10u);
                buf[2] = (char)('0' + eid % 10u);
            } else {
                buf[1] = (char)('0' + eid);
            }
        }
        break;

    case 8u: /* TWM: data = cpu_pct(8) | gpu_pct(8) */
        {
            uint8_t cpu = (uint8_t)(data >> 8u);
            uint8_t gpu = (uint8_t)(data & 0xFFu);
            write_text(buf, 0, "CPU:");
            if (cpu >= 100u) {
                buf[4] = '1'; buf[5] = '0'; buf[6] = '0';
            } else if (cpu >= 10u) {
                buf[5] = (char)('0' + cpu / 10u);
                buf[6] = (char)('0' + cpu % 10u);
            } else {
                buf[6] = (char)('0' + cpu);
            }
            buf[7] = '%';
            write_text(buf, 9, "G:");
            if (gpu >= 100u) {
                buf[11] = '1'; buf[12] = '0'; buf[13] = '0';
            } else if (gpu >= 10u) {
                buf[12] = (char)('0' + gpu / 10u);
                buf[13] = (char)('0' + gpu % 10u);
            } else {
                buf[13] = (char)('0' + gpu);
            }
            buf[14] = '%';
        }
        break;

    case 9u: /* CONWAY: data = gen_lo(8) | pop_lo(8) */
        {
            uint8_t gen = (uint8_t)(data >> 8u);
            uint8_t pop = (uint8_t)(data & 0xFFu);
            buf[0] = 'G';
            buf[1] = ':';
            if (gen >= 100u) {
                buf[2] = (char)('0' + gen / 100u);
                buf[3] = (char)('0' + (gen / 10u) % 10u);
                buf[4] = (char)('0' + gen % 10u);
            } else if (gen >= 10u) {
                buf[2] = (char)('0' + gen / 10u);
                buf[3] = (char)('0' + gen % 10u);
            } else {
                buf[2] = (char)('0' + gen);
            }
            buf[9] = 'P';
            buf[10] = ':';
            if (pop >= 100u) {
                buf[11] = (char)('0' + pop / 100u);
                buf[12] = (char)('0' + (pop / 10u) % 10u);
                buf[13] = (char)('0' + pop % 10u);
            } else if (pop >= 10u) {
                buf[11] = (char)('0' + pop / 10u);
                buf[12] = (char)('0' + pop % 10u);
            } else {
                buf[11] = (char)('0' + pop);
            }
        }
        break;

    case 10u: /* NTT: progress bar via flags=sub_id, data=progress% */
        render_progress_bar(buf, "NTT", (uint8_t)(data & 0xFFu));
        break;

    case 11u: /* SYNTH: data = note_l(8) | note_r(8) (MIDI note#) */
        {
            static const char note_names[] = "CCDDEFFGGAAB";
            static const char sharp_map[]  = " # #  # # # ";
            uint8_t ml = (uint8_t)(data >> 8u);
            uint8_t mr = (uint8_t)(data & 0xFFu);
            /* L channel */
            buf[0] = 'L';
            buf[1] = ':';
            if (ml == 0u) {
                buf[2] = '-'; buf[3] = '-';
            } else {
                buf[2] = note_names[ml % 12u];
                buf[3] = (sharp_map[ml % 12u] == '#') ? '#' : ' ';
                buf[4] = (char)('0' + (ml / 12u) - 1u);
            }
            /* R channel */
            buf[8] = 'R';
            buf[9] = ':';
            if (mr == 0u) {
                buf[10] = '-'; buf[11] = '-';
            } else {
                buf[10] = note_names[mr % 12u];
                buf[11] = (sharp_map[mr % 12u] == '#') ? '#' : ' ';
                buf[12] = (char)('0' + (mr / 12u) - 1u);
            }
        }
        break;

    case 12u: /* PFORTH: data = stack_depth(16) */
        write_text(buf, 0, "DEPTH:");
        {
            unsigned d = data & 0xFFFFu;
            char tmp[6];
            int pos = 0;
            if (d == 0u) { tmp[pos++] = '0'; }
            else {
                unsigned v = d;
                while (v > 0u && pos < 5) {
                    tmp[pos++] = (char)('0' + v % 10u);
                    v /= 10u;
                }
            }
            for (int i = pos - 1; i >= 0; i--) {
                buf[6 + (pos - 1 - i)] = tmp[i];
            }
        }
        write_text(buf, 12, "OK");
        break;

    default:
        write_text(buf, 0, "UNKNOWN");
        break;
    }

    (void)state;
}

/* ── Render dispatch ─────────────────────────────────────────────── */

static void lcd_render_program(uint8_t prog_id, uint8_t state,
                               uint8_t flags, uint16_t data) {
    char line1[16];
    char line2[16];
    build_line1(line1, prog_id);
    render_line2(line2, prog_id, state, flags, data);
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

/* ── Public API ──────────────────────────────────────────────────── */

static uint32_t compose_program_word(uint8_t prog_id, uint8_t state,
                                     uint8_t flags, uint16_t data) {
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
    lcd_render_program(0u, BOARD_STATE_READY, 0u, 0u);
}

void board_status_release(void) {
    claimed = 0;
}

int board_status_claimed(void) {
    return claimed;
}

void board_status_set_program(uint8_t prog_id, uint8_t state,
                             uint8_t flags, uint16_t data) {
    uint32_t word = compose_program_word(prog_id, state, flags, data);
    claimed = 1;
    if (word != current_word) {
        current_word = word;
        gpio_write_out(word);
    }
    lcd_render_program(prog_id, state, flags, data);
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
    lcd_render_program(prog_id, state, 0u, 0u);
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
