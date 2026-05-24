/*
 * DE2Extra — SDRAM 读写测试
 *
 * 测试模式:
 *   1. Walking 1s immediate
 *   2. Walking 1s bulk
 *   3. Checkerboard
 *   4. Address-as-data
 *   5. Sparse boundary probes
 *
 * SDRAM 基址: 0x01000000 (XBUS → sdram_ctrl)
 * 密集测试大小: 4096 words (16KB)
 *
 * GPIO/LCD 调试协议:
 *   0x0------- : LCD 显示 TESTING
 *   0x1------- : LCD 显示 ALL PASS
 *   0x8tww0000 : fail meta, t=test#, ww=word index
 *   0x9---hhhh : fail got[31:16]
 *   0xA---llll : fail got[15:0]
 */
#include <neorv32.h>

#define BAUD_RATE 115200
#define SDRAM_BASE ((volatile uint32_t *)0x01000000)
#define TEST_WORDS 4096

#define LCD_STATUS_TESTING   0x00000000u
#define LCD_STATUS_PASS      0x10000000u
#define LCD_FAIL_META        0x80000000u
#define LCD_FAIL_GOT_HI      0x90000000u
#define LCD_FAIL_GOT_LO      0xA0000000u

static int all_pass = 1;
static uint32_t fail_word = 0;
static uint32_t fail_test = 0;
static uint32_t fail_addr = 0;
static uint32_t fail_expected = 0;
static uint32_t fail_got = 0;

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

static uint32_t sparse_pattern(uint32_t word_idx) {
    return 0xA5A50000u ^ (word_idx * 0x1F123BB5u) ^ (word_idx >> 3);
}

static void lcd_status(uint32_t s) {
    neorv32_gpio_port_set(s);
}

static void short_delay(void) {
    for (volatile int i = 0; i < 2000; i++) {
        __asm__ volatile("nop");
    }
}

static void record_fail(uint32_t test_num, uint32_t word_idx, uint32_t expected, uint32_t got) {
    if (all_pass) {
        fail_test = test_num;
        fail_word = word_idx;
        fail_addr = (uint32_t)(SDRAM_BASE + word_idx);
        fail_expected = expected;
        fail_got = got;
    }
    all_pass = 0;
}

static void print_fail_report(void) {
    neorv32_uart0_printf("\n[FAIL] test=%u word=%u addr=0x%x expected=0x%x got=0x%x\n",
        fail_test, fail_word, fail_addr, fail_expected, fail_got);
}

static void lcd_show_fail(void) {
    lcd_status(LCD_FAIL_META | ((fail_test & 0x0Fu) << 24) | ((fail_word & 0xFFu) << 16));
    short_delay();
    lcd_status(LCD_FAIL_GOT_HI | ((fail_got >> 16) & 0xFFFFu));
    short_delay();
    lcd_status(LCD_FAIL_GOT_LO | (fail_got & 0xFFFFu));
}

static void test_walking_ones_immediate(void) {
    neorv32_uart0_puts("[TEST1] walking ones immediate...\n");

    for (int i = 0; i < TEST_WORDS; i++) {
        uint32_t expected = (uint32_t)1 << (i % 32);
        SDRAM_BASE[i] = expected;
        uint32_t got = SDRAM_BASE[i];
        if (got != expected) {
            record_fail(1, i, expected, got);
            return;
        }
    }

    neorv32_uart0_puts("[PASS] test1\n");
}

static void test_walking_ones_bulk(void) {
    neorv32_uart0_puts("[TEST2] walking ones bulk...\n");

    for (int i = 0; i < TEST_WORDS; i++) {
        SDRAM_BASE[i] = (uint32_t)1 << (i % 32);
    }
    for (int i = 0; i < TEST_WORDS; i++) {
        uint32_t expected = (uint32_t)1 << (i % 32);
        uint32_t got = SDRAM_BASE[i];
        if (got != expected) {
            record_fail(2, i, expected, got);
            return;
        }
    }

    neorv32_uart0_puts("[PASS] test2\n");
}

static void test_checkerboard(void) {
    neorv32_uart0_puts("[TEST3] checkerboard...\n");

    for (int i = 0; i < TEST_WORDS; i++) {
        SDRAM_BASE[i] = (i & 1) ? 0xAAAAAAAA : 0x55555555;
    }

    for (int i = 0; i < TEST_WORDS; i++) {
        uint32_t expected = (i & 1) ? 0xAAAAAAAA : 0x55555555;
        uint32_t got = SDRAM_BASE[i];
        if (got != expected) {
            record_fail(3, i, expected, got);
            return;
        }
    }

    neorv32_uart0_puts("[PASS] test3\n");
}

static void test_address_data(void) {
    neorv32_uart0_puts("[TEST4] address-as-data...\n");

    for (int i = 0; i < TEST_WORDS; i++) {
        SDRAM_BASE[i] = (uint32_t)(SDRAM_BASE + i);
    }

    for (int i = 0; i < TEST_WORDS; i++) {
        uint32_t expected = (uint32_t)(SDRAM_BASE + i);
        uint32_t got = SDRAM_BASE[i];
        if (got != expected) {
            record_fail(4, i, expected, got);
            return;
        }
    }

    neorv32_uart0_puts("[PASS] test4\n");
}

static void test_sparse_boundaries(void) {
    neorv32_uart0_puts("[TEST5] sparse boundary probes...\n");

    for (uint32_t i = 0; i < (uint32_t)(sizeof(sparse_words) / sizeof(sparse_words[0])); i++) {
        uint32_t word_idx = sparse_words[i];
        SDRAM_BASE[word_idx] = sparse_pattern(word_idx);
    }

    for (uint32_t i = 0; i < (uint32_t)(sizeof(sparse_words) / sizeof(sparse_words[0])); i++) {
        uint32_t word_idx = sparse_words[i];
        uint32_t expected = sparse_pattern(word_idx);
        uint32_t got = SDRAM_BASE[word_idx];
        if (got != expected) {
            record_fail(5, word_idx, expected, got);
            return;
        }
    }

    neorv32_uart0_puts("[PASS] test5\n");
}

static void dump_fail_window(void) {
    uint32_t start = (fail_word > 1u) ? (fail_word - 1u) : 0u;
    uint32_t stop = fail_word + 2u;

    neorv32_uart0_printf("\n[DIAG] fail window around word=%u\n", fail_word);
    for (uint32_t word_idx = start; word_idx <= stop; word_idx++) {
        uint32_t got = SDRAM_BASE[word_idx];
        neorv32_uart0_printf("[DIAG] w%u -> 0x%x\n", word_idx, got);
    }
}

/* 等待 SDRAM 控制器完成初始化。给 1ms 左右余量，避免上电边界影响测试结果。 */
static void sdram_wait_init(void) {
    for (volatile int i = 0; i < 50000; i++) {
        __asm__ volatile("nop");
    }
}

int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD_RATE, 0);
    neorv32_gpio_dir_set(0xFFFFFFFF);

    neorv32_uart0_puts("\n=== DE2Extra SDRAM self-test ===\n");
    neorv32_uart0_printf("base=0x%x dense_words=%u sparse_points=%u\n",
        (uint32_t)SDRAM_BASE,
        (uint32_t)TEST_WORDS,
        (uint32_t)(sizeof(sparse_words) / sizeof(sparse_words[0])));

    sdram_wait_init();
    neorv32_uart0_puts("init wait done\n");
    lcd_status(LCD_STATUS_TESTING);

    test_walking_ones_immediate();
    if (all_pass) {
        test_walking_ones_bulk();
    }
    if (all_pass) {
        test_checkerboard();
    }
    if (all_pass) {
        test_address_data();
    }
    if (all_pass) {
        test_sparse_boundaries();
    }

    if (all_pass) {
        neorv32_uart0_puts("[PASS] all tests passed\n");
        lcd_status(LCD_STATUS_PASS);
    } else {
        print_fail_report();
        lcd_show_fail();
        dump_fail_window();
    }

    while (1) {}
    return 0;
}
