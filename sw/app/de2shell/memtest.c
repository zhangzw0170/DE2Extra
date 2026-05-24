/* memtest.c — SDRAM 读写自检 (Phase 1)
 *
 * 4 项测试: walking-ones immediate/bulk, checkerboard, address-as-data
 * 结果通过 VGA 显示，同时驱动 GPIO/LCD 调试协议
 */
#include "vga_hal.h"
#include "gpio_hal.h"
#include <stddef.h>

#define SDRAM_BASE  ((volatile uint32_t *)0x01000000)
#define TEST_WORDS  256
#define CASE_LIST_ROW 3
#define CASE_RESULT_ROW 11
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

static const char *test_names[4] = {
    "Case 1  Walking-1 immediate",
    "Case 2  Walking-1 bulk     ",
    "Case 3  Checkerboard       ",
    "Case 4  Address-as-data    "
};

static const char *test_descs[4] = {
    "per-word write/read 1<<(i%32)",
    "bulk write then bulk readback ",
    "0x55555555 <-> 0xAAAAAAAA     ",
    "write physical address value  "
};

static void lcd_status(uint32_t s) {
#ifndef LOCAL_BUILD
    neorv32_gpio_port_set(s);
#endif
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

/* 每次调用 run_one_step() 执行一项测试并更新 VGA */
static void run_test(int test_id) {
    if (test_id < 0 || test_id >= 4) return;
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
    for (int i = 0; i < 4; i++) {
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

    /* LOCAL_BUILD: 标记所有测试通过 (模拟) */
#ifdef LOCAL_BUILD
    /* 模拟 SDRAM 测试全部通过 */
#endif
}

static void update(void) {
    if (finished) return;

    if (current_test < 4 && all_pass) {
        run_test(current_test);
        current_test++;
    }

    if (current_test >= 4 || !all_pass) {
        finished = 1;
        vga_goto(0, SUMMARY_ROW);
        if (all_pass) {
            vga_puts("[ALL PASS] All 4 SDRAM cases passed.", VGA_GREEN);
            lcd_status(LCD_STATUS_PASS);
        } else {
            vga_puts("[FAIL] T", VGA_RED);
            const char hex[] = "0123456789ABCDEF";
            vga_putc(hex[fail_test & 0xF], VGA_RED);
            vga_puts(" W", VGA_RED);
            /* 显示 word index (2 hex digits) */
            vga_putc(hex[(fail_word >> 4) & 0xF], VGA_RED);
            vga_putc(hex[fail_word & 0xF], VGA_RED);
            vga_puts(" GOT ", VGA_RED);
            /* 显示 got 值 (8 hex) */
            for (int i = 7; i >= 0; i--)
                vga_putc(hex[(fail_got >> (i*4)) & 0xF], VGA_RED);
            lcd_status(LCD_FAIL_META |
                       ((fail_test & 0xF) << 24) |
                       ((fail_word & 0xFF) << 16));
            lcd_status(LCD_FAIL_GOT_HI | ((fail_got >> 16) & 0xFFFFu));
            lcd_status(LCD_FAIL_GOT_LO | (fail_got & 0xFFFFu));
            vga_goto(0, DETAIL_ROW);
            vga_puts("EXP ", VGA_RED);
            vga_puthex32(fail_expected);
            vga_puts("  GOT ", VGA_RED);
            vga_puthex32(fail_got);
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
    "MemTest", "SDRAM 4-test self-check",
    init, update, input, NULL, finish
};
