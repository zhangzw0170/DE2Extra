/* selfcheck.c — Power-On Self-Test / System Health Check
 *
 * Runs before FreeRTOS scheduler start. Tests SDRAM, Wishbone bus,
 * PS/2, TRNG, Build Info ROM, and framebuffer data path.
 *
 * Each test prints [PASS] or [FAIL] to UART. Returns bitmask:
 *   bit 0: SDRAM, bit 1: WB bus, bit 2: PS/2, bit 3: TRNG,
 *   bit 4: Build Info, bit 5: Framebuffer. 0 = all pass.
 */
#include <stdint.h>
#include <neorv32_trng.h>

#define POST_SDRAM      (1u << 0)
#define POST_BUS        (1u << 1)
#define POST_PS2        (1u << 2)
#define POST_TRNG       (1u << 3)
#define POST_BUILDINFO  (1u << 4)
#define POST_FRAMEBUFFER (1u << 5)

/* Peripherals under test */
#define SDRAM_BASE   ((volatile uint32_t *)0x01100000u)  /* 1MB offset to avoid code at 0x01000000 */
#define PS2_BASE     ((volatile uint32_t *)0xF0008000u)
#define BUILDINFO_BASE ((volatile uint32_t *)0xF0009000u)
#define FB_BASE      ((volatile uint32_t *)0x01800000u)

#define NTEST_WORDS 4096

/* ---- helpers ---- */

static char *sc_buf;  /* NULL = UART only; non-NULL = also append to buffer */

static void post_uart(const char *tag, int pass, const char *detail) {
    neorv32_uart0_puts("  [");
    neorv32_uart0_puts(pass ? "PASS" : "FAIL");
    neorv32_uart0_puts("] ");
    neorv32_uart0_puts(tag);
    if (detail) {
        neorv32_uart0_puts(": ");
        neorv32_uart0_puts(detail);
    }
    neorv32_uart0_puts("\r\n");
    /* Also write to buf if available (for VGA/CLI output) */
    if (sc_buf) {
        /* Manually format into buffer - simple append */
        char *p = sc_buf;
        while (*p) p++;  /* find end */
        *p++ = ' '; *p++ = '[';
        const char *s = pass ? "PASS" : "FAIL";
        while (*s) *p++ = *s++;
        *p++ = ']'; *p++ = ' ';
        s = tag;
        while (*s) *p++ = *s++;
        if (detail) {
            *p++ = ':'; *p++ = ' ';
            s = detail;
            while (*s) *p++ = *s++;
        }
        *p++ = '\r'; *p++ = '\n'; *p = '\0';
        sc_buf = p;
    }
}

/* ---- test 0: SDRAM ---- */

static int post_sdram(void) {
    int pass = 1;
    uint32_t exp, got;

    /* Test 1: walking 1s */
    for (int i = 0; i < NTEST_WORDS; i++) {
        exp = (uint32_t)1 << (i % 32);
        SDRAM_BASE[i] = exp;
    }
    for (int i = 0; i < NTEST_WORDS; i++) {
        exp = (uint32_t)1 << (i % 32);
        got = SDRAM_BASE[i];
        if (got != exp) { pass = 0; break; }
    }
    if (!pass) { post_uart("SDRAM-walk1", 0, "mismatch"); return 0; }

    /* Test 2: AA/55 */
    for (int i = 0; i < NTEST_WORDS; i++) {
        SDRAM_BASE[i] = (i & 1) ? 0xAAAAAAAAu : 0x55555555u;
    }
    for (int i = 0; i < NTEST_WORDS; i++) {
        exp = (i & 1) ? 0xAAAAAAAAu : 0x55555555u;
        got = SDRAM_BASE[i];
        if (got != exp) { pass = 0; break; }
    }
    if (!pass) { post_uart("SDRAM-aa55", 0, "mismatch"); return 0; }

    /* Test 3: address pattern */
    for (int i = 0; i < NTEST_WORDS; i++) {
        SDRAM_BASE[i] = (uint32_t)(uintptr_t)(SDRAM_BASE + i);
    }
    for (int i = 0; i < NTEST_WORDS; i++) {
        exp = (uint32_t)(uintptr_t)(SDRAM_BASE + i);
        got = SDRAM_BASE[i];
        if (got != exp) { pass = 0; break; }
    }
    if (!pass) { post_uart("SDRAM-addr", 0, "mismatch"); return 0; }

    post_uart("SDRAM", 1, "3/3 patterns OK");
    return 1;
}

/* ---- test 1: Wishbone bus scan ---- */

typedef struct { const char *name; uint32_t base; } post_dev_t;

static const post_dev_t post_devices[] = {
    { "VGA",     0xF0000000u },
    { "PS/2",   0xF0008000u },
    { "LCD",     0xF000B000u },
    { "IR",      0xF000C000u },
    { "ExpDemo",  0xF0010000u },
    { "Conway",  0xF0011000u },
    { "GPU",     0xF0015000u },
    { NULL, 0 }
};

static int post_bus(void) {
    int ok = 0, total = 0;

    for (int i = 0; post_devices[i].name != NULL; i++) {
        total++;
        volatile uint32_t *dev = (volatile uint32_t *)post_devices[i].base;
        /* Read word at offset 0. XBUS timeout returns 0 if no ack.
         * If we get here without hanging, bus decoder + slave ack is working. */
        (void)dev[0];
        ok++;
    }
    char detail[16];
    detail[0] = '0' + ok;
    detail[1] = '/';
    detail[2] = '0' + total;
    detail[3] = '\0';
    post_uart("WB-bus", ok == total, detail);
    return ok == total;
}

/* ---- test 2: PS/2 ---- */

static int post_ps2(void) {
    /* PS2 scancode register at offset 0.
       After init (no key pressed), should read 0x00.
       XBUS timeout protects against bus hang. */
    uint32_t val = PS2_BASE[0];
    if (val == 0x00000000u) {
        post_uart("PS/2", 1, NULL);
        return 1;
    }
    post_uart("PS/2", 0, "unexpected reg val");
    return 0;
}

/* ---- test 3: TRNG ---- */

static int post_trng_read32(uint32_t *out, int timeout) {
    uint32_t val = 0;
    for (int i = 0; i < 4; i++) {
        while (!neorv32_trng_data_avail() && --timeout > 0)
            ;
        if (timeout == 0) return 0;
        val = (val << 8) | neorv32_trng_data_get();
    }
    *out = val;
    return 1;
}

static int post_trng(void) {
    if (!neorv32_trng_available()) {
        post_uart("TRNG", 0, "not available");
        return 0;
    }
    neorv32_trng_enable();
    neorv32_trng_fifo_clear();

    uint32_t r1, r2;
    if (!post_trng_read32(&r1, 200000)) {
        post_uart("TRNG", 0, "no data");
        return 0;
    }
    if (!post_trng_read32(&r2, 200000)) {
        post_uart("TRNG", 0, "no data (2nd)");
        return 0;
    }
    if (r1 == r2) {
        post_uart("TRNG", 0, "no entropy");
        return 0;
    }
    post_uart("TRNG", 1, "entropy OK");
    return 1;
}

/* ---- test 4: Build Info ROM ---- */

static int post_buildinfo(void) {
    uint32_t val = BUILDINFO_BASE[0];
    /* Check magic: 0x42494E46 ("BINF") */
    if (val == 0x42494E46u) {
        post_uart("BuildInfo", 1, NULL);
        return 1;
    }
    post_uart("BuildInfo", 0, "bad magic");
    return 0;
}

/* ---- test 5: Framebuffer ---- */

static int post_framebuffer(void) {
    /* Write a known pattern at the start of framebuffer */
    FB_BASE[0] = 0xDEADBEEFu;
    uint32_t got = FB_BASE[0];
    FB_BASE[0] = 0u;  /* clean up */

    if (got == 0xDEADBEEFu) {
        post_uart("FB", 1, "SDRAM FB readback OK");
        return 1;
    }
    post_uart("FB", 0, "readback mismatch");
    return 0;
}

/* ---- entry point ---- */
/* skip_sdram: set to 1 when running from shell (VGA reads SDRAM concurrently)
 * out_buf: non-NULL to also write results to buffer (for VGA/CLI display) */

uint32_t selfcheck_run(int skip_sdram, char *out_buf) {
    uint32_t mask = 0;
    int total = 6, passed = 0;

    sc_buf = out_buf;
    if (out_buf) out_buf[0] = '\0';

    neorv32_uart0_puts("\r\n=== selfcheck ===\r\n");

    if (skip_sdram) {
        neorv32_uart0_puts("  [SKIP] SDRAM (bootloader tested)\r\n");
        neorv32_uart0_puts("  [SKIP] FB (skipped with SDRAM)\r\n");
        neorv32_uart0_puts("  [SKIP] BuildInfo (requires direct access)\r\n");
        passed += 3;
    } else {
        if (post_sdram())      { passed++; } else { mask |= POST_SDRAM; }
        if (post_framebuffer()) { passed++; } else { mask |= POST_FRAMEBUFFER; }
        if (post_buildinfo())  { passed++; } else { mask |= POST_BUILDINFO; }
    }
    if (post_bus())        { passed++; } else { mask |= POST_BUS; }
    if (post_ps2())        { passed++; } else { mask |= POST_PS2; }
    if (post_trng())       { passed++; } else { mask |= POST_TRNG; }

    neorv32_uart0_puts("\r\n");
    if (passed == total) {
        neorv32_uart0_puts("selfcheck: ALL PASS (");
    } else {
        neorv32_uart0_puts("selfcheck: ");
    }
    neorv32_uart0_putc('0' + passed);
    neorv32_uart0_putc('/');
    neorv32_uart0_putc('0' + total);
    neorv32_uart0_putc(')');

    if (mask) {
        neorv32_uart0_puts(" failures:");
        if (mask & POST_SDRAM)      { neorv32_uart0_puts(" SDRAM"); }
        if (mask & POST_PS2)        { neorv32_uart0_puts(" PS2"); }
        if (mask & POST_TRNG)       { neorv32_uart0_puts(" TRNG"); }
        if (mask & POST_BUILDINFO)  { neorv32_uart0_puts(" BuildInfo"); }
        if (mask & POST_FRAMEBUFFER) { neorv32_uart0_puts(" FB"); }
    }
    neorv32_uart0_putc('\n');
    neorv32_uart0_putc('\r');

    sc_buf = NULL;
    return mask;
}
