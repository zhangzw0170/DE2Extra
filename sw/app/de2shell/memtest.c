/* memtest.c — SDRAM 读写自检
 *
 * 5 项测试: walking-ones immediate/bulk, checkerboard, address-as-data, sparse boundary
 * 结果通过 VGA 显示，同时驱动 GPIO/LCD 调试协议
 *
 * 独立诊断程序: sw/app/sdram_test/ (4096 words, UART-only, "维修模式")
 */
#include "vga_hal.h"
#include "gpio_hal.h"
#include "lcd_hal.h"
#include <stddef.h>

#define SDRAM_BASE  ((volatile uint32_t *)0x01000000)
#define TEST_WORDS  1024
#define CASE_LIST_ROW 3
#define CASE_RESULT_ROW 10
#define SUMMARY_ROW 16
#define DETAIL_ROW 17
#define PROMPT_ROW 19

/* LCD 调试协议 */
#define LCD_STATUS_TESTING  0x00000000u
#define LCD_STATUS_PASS     0x10000000u
#define LCD_FAIL_META       0x80000000u
#define LCD_FAIL_GOT_HI     0x90000000u
#define LCD_FAIL_GOT_LO     0xA0000000u

static int all_pass;
static int current_test;
static uint32_t fail_word, fail_test, fail_got, fail_expected;
static int finished;
static int done;

static const char *test_names[5] = {
    "Case 1  Walking-1 immediate",
    "Case 2  Walking-1 bulk     ",
    "Case 3  Checkerboard       ",
    "Case 4  Address-as-data    ",
    "Case 5  Sparse boundary    "
};

static const char *test_descs[5] = {
    "per-word write/read 1<<(i%32)",
    "bulk write then bulk readback ",
    "0x55555555 <-> 0xAAAAAAAA     ",
    "write physical address value  ",
    "31 sparse boundary probes     "
};

/* Sparse boundary probe offsets (from sdram_test) */
static const uint32_t sparse_words[] = {
    0x00000000u, 0x00000001u, 0x00000002u, 0x00000003u,
    0x000000FFu, 0x00000100u, 0x00000101u,
    0x000001FFu, 0x00000200u, 0x00000201u,
    0x000003FFu, 0x00000400u, 0x00000401u,
    0x000007FFu, 0x00000800u, 0x00000801u,
    0x00000FFFu, 0x00001000u, 0x00001001u,
    0x00001FFFu, 0x00002000u, 0x00002001u,
    0x0000FFFFu, 0x00010000u, 0x00010001u,
    0x000FFFFFu, 0x00100000u, 0x00100001u,
    0x007FFFFFu, 0x00800000u, 0x00800001u
};
#define SPARSE_COUNT (sizeof(sparse_words) / sizeof(sparse_words[0]))

static uint32_t sparse_pattern(uint32_t word_idx) {
    return 0xA5A50000u ^ (word_idx * 0x1F123BB5u) ^ (word_idx >> 3);
}

static char hex_digit(unsigned value) {
    value &= 0x0fu;
    return (value < 10u) ? (char)('0' + value) : (char)('A' + (value - 10u));
}

static void lcd_show_fail(uint32_t test_num, uint32_t word_idx, uint32_t got) {
    char line1[17] = "                ";
    char line2[17] = "                ";

    line1[0] = 'F'; line1[1] = 'A'; line1[2] = 'I'; line1[3] = 'L';
    line1[4] = ' '; line1[5] = 'T'; line1[6] = hex_digit(test_num);
    line1[7] = ' '; line1[8] = 'W';
    line1[9] = hex_digit((word_idx >> 4) & 0x0fu);
    line1[10] = hex_digit(word_idx & 0x0fu);

    line2[0] = 'G'; line2[1] = 'O'; line2[2] = 'T'; line2[3] = ' ';
    for (int i = 0; i < 8; i++) {
        line2[4 + i] = hex_digit((unsigned)(got >> ((7 - i) * 4)));
    }

    lcd_write_lines(line1, line2);
}

static void lcd_status(uint32_t s) {
    char line1[17] = "DE2Extra SDRAM  ";
    char line2[17] = "                ";

    if (s == LCD_STATUS_TESTING) {
        line2[0] = 'T'; line2[1] = 'E'; line2[2] = 'S'; line2[3] = 'T';
        line2[4] = 'I'; line2[5] = 'N'; line2[6] = 'G'; line2[7] = '.';
        line2[8] = '.'; line2[9] = '.';
    } else if (s == LCD_STATUS_PASS) {
        line2[0] = 'A'; line2[1] = 'L'; line2[2] = 'L'; line2[3] = ' ';
        line2[4] = 'P'; line2[5] = 'A'; line2[6] = 'S'; line2[7] = 'S';
    }

    lcd_write_lines(line1, line2);
}

static void put_hex32_color(uint32_t val, uint16_t color) {
    static const char hex[] = "0123456789ABCDEF";

    for (int i = 7; i >= 0; i--) {
        vga_putc(hex[(val >> (i * 4)) & 0x0f], color);
    }
}

static void record_fail(uint32_t test_num, uint32_t word_idx,
                        uint32_t expected, uint32_t got) {
    if (all_pass) {
        fail_test = test_num;
        fail_word = word_idx;
        fail_expected = expected;
        fail_got = got;
    }
    all_pass = 0;
}

static void run_test(int test_id) {
    if (test_id < 0 || test_id >= 5) return;
    vga_goto(0, CASE_RESULT_ROW + test_id);

    int pass = 1;
    switch (test_id) {
    case 0: /* Walking-1s immediate */
        for (int i = 0; i < TEST_WORDS; i++) {
            uint32_t exp = (uint32_t)1 << (i % 32);
            uint32_t got;
            SDRAM_BASE[i] = exp;
            got = SDRAM_BASE[i];
            if (got != exp) {
                record_fail(1, i, exp, got);
                pass = 0; break;
            }
        }
        break;
    case 1: /* Walking-1s bulk */
        for (int i = 0; i < TEST_WORDS; i++)
            SDRAM_BASE[i] = (uint32_t)1 << (i % 32);
        for (int i = 0; i < TEST_WORDS; i++) {
            uint32_t exp = (uint32_t)1 << (i % 32);
            uint32_t got = SDRAM_BASE[i];
            if (got != exp) {
                record_fail(2, i, exp, got);
                pass = 0; break;
            }
        }
        break;
    case 2: /* Checkerboard */
        for (int i = 0; i < TEST_WORDS; i++)
            SDRAM_BASE[i] = (i & 1) ? 0xAAAAAAAA : 0x55555555;
        for (int i = 0; i < TEST_WORDS; i++) {
            uint32_t exp = (i & 1) ? 0xAAAAAAAA : 0x55555555;
            uint32_t got = SDRAM_BASE[i];
            if (got != exp) {
                record_fail(3, i, exp, got);
                pass = 0; break;
            }
        }
        break;
    case 3: /* Address-as-data */
        for (int i = 0; i < TEST_WORDS; i++)
            SDRAM_BASE[i] = (uint32_t)(uintptr_t)(SDRAM_BASE + i);
        for (int i = 0; i < TEST_WORDS; i++) {
            uint32_t exp = (uint32_t)(uintptr_t)(SDRAM_BASE + i);
            uint32_t got = SDRAM_BASE[i];
            if (got != exp) {
                record_fail(4, i, exp, got);
                pass = 0; break;
            }
        }
        break;
    case 4: /* Sparse boundary probes */
        for (uint32_t i = 0; i < SPARSE_COUNT; i++) {
            uint32_t idx = sparse_words[i];
            SDRAM_BASE[idx] = sparse_pattern(idx);
        }
        for (uint32_t i = 0; i < SPARSE_COUNT; i++) {
            uint32_t idx = sparse_words[i];
            uint32_t exp = sparse_pattern(idx);
            uint32_t got = SDRAM_BASE[idx];
            if (got != exp) {
                record_fail(5, idx, exp, got);
                pass = 0; break;
            }
        }
        break;
    }

    vga_puts(test_names[test_id], VGA_WHITE);
    vga_puts(" : ", VGA_WHITE);
    if (pass) {
        vga_puts("PASS", VGA_GREEN);
    } else {
        vga_puts("FAIL", VGA_RED);
    }
}

static void init(void) {
    all_pass = 1;
    current_test = 0;
    finished = 0;
    done = 0;
    fail_word = fail_test = fail_got = fail_expected = 0;

    vga_clear();
    vga_goto(0, 0);
    vga_puts("MemTest — SDRAM Self-Test\n", VGA_CYAN);
    vga_puts("========================\n", VGA_WHITE);
    vga_puts("Test cases:\n", VGA_GRAY);
    for (int i = 0; i < 5; i++) {
        vga_puts("  ", VGA_BLACK);
        vga_puts(test_names[i], VGA_WHITE);
        vga_puts("\n", VGA_WHITE);
        vga_puts("     ", VGA_BLACK);
        vga_puts(test_descs[i], VGA_GRAY);
        vga_puts("\n", VGA_GRAY);
    }

#ifndef LOCAL_BUILD
    vga_goto(0, CASE_RESULT_ROW - 1);
    vga_puts("Waiting for SDRAM init...", VGA_GRAY);
    for (volatile int i = 0; i < 50000; i++) __asm__ volatile("nop");
    vga_goto(0, CASE_RESULT_ROW - 1);
    vga_puts("                          ", VGA_BLACK);
#endif

    lcd_status(LCD_STATUS_TESTING);
}

static void update(void) {
    if (finished) return;

    if (current_test < 5 && all_pass) {
        run_test(current_test);
        current_test++;
    }

    if (current_test >= 5 || !all_pass) {
        finished = 1;
        vga_goto(0, SUMMARY_ROW);
        if (all_pass) {
            vga_puts("[ALL PASS] All 5 SDRAM cases passed.", VGA_GREEN);
            lcd_status(LCD_STATUS_PASS);
        } else {
            uint32_t fail_addr = (uint32_t)(uintptr_t)(SDRAM_BASE + fail_word);

            vga_puts("[FAIL] T=", VGA_RED);
            put_hex32_color(fail_test, VGA_RED);
            vga_puts(" W=", VGA_RED);
            put_hex32_color(fail_word, VGA_RED);
            vga_puts(" A=", VGA_RED);
            put_hex32_color(fail_addr, VGA_RED);
            lcd_show_fail(fail_test, fail_word, fail_got);
            vga_goto(0, DETAIL_ROW);
            vga_puts("EXP ", VGA_RED);
            put_hex32_color(fail_expected, VGA_YELLOW);
            vga_puts("  GOT ", VGA_RED);
            put_hex32_color(fail_got, VGA_YELLOW);
        }
        vga_goto(0, PROMPT_ROW);
        vga_puts("Press 'q' to return, 'r' to retest\n", VGA_GRAY);
    }
}

static void input(char c) {
    if (c == 'q' || c == 'Q') {
        done = 1;
        return;
    }
    if (c == 'r' || c == 'R') {
        init();
    }
}

static int finish(void) { return done; }

const program_t prog_memtest = {
    "MemTest", "SDRAM 5-test self-check",
    init, update, input, NULL, finish
};
