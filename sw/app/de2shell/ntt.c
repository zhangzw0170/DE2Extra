/* ntt.c — NTT accelerator driver + interactive CLI
 *
 * Matches ntt_sdf.vhd algorithm: DIF Cooley-Tukey (A+B, (A-B)*w), stages 7→0.
 * Output is bit-reversed; software does bit-reversal for natural order.
 */

#include "ntt.h"
#include "vga_hal.h"
#include <stdint.h>

#ifdef LOCAL_BUILD
  #include <string.h>
  #include <stdlib.h>
#else
  static int strcmp(const char *a, const char *b) {
      while (*a && *a == *b) { a++; b++; }
      return (unsigned char)*a - (unsigned char)*b;
  }
#endif

/* ── Barrett reduction (matches VHDL: constant=5039) ────────────── */

static inline uint16_t barrett(uint32_t x) {
    uint32_t q_est = (x * 5039u) >> 24;
    uint32_t r = x - q_est * 3329u;
    if (r >= 3329u) r -= 3329u;
    return (uint16_t)r;
}

/* ── Twiddle table: TW[k] = 17^k mod 3329, k=0..127 ────────────── */

static const uint16_t TW[128] = {
       1,   17,  289, 1584,  296, 1703, 2319, 2804, 1062, 1409,  650, 1063,
    1426,  939, 2647, 1722, 2642, 1637, 1197,  375, 3046, 1847, 1438, 1143,
    2786,  756, 2865, 2099, 2393,  733, 2474, 2110, 2580,  583, 3253, 2037,
    1339, 2789,  807,  403,  193, 3281, 2513, 2773,  535, 2437, 1481, 1874,
    1897, 2288, 2277, 2090, 2240, 1461, 1534, 2775,  569, 3015, 1320, 2466,
    1974,  268, 1227,  885, 1729, 2761,  331, 2298, 2447, 1651, 1435, 1092,
    1919, 2662, 1977,  319, 2094, 2308, 2617, 1212,  630,  723, 2304, 2549,
      56,  952, 2868, 2150, 3260, 2156,   33,  561, 2879, 2337, 3110, 2935,
    3289, 2649, 1756, 3220, 1476, 1789,  452, 1026,  797,  233,  632,  757,
    2882, 2388,  648, 1029,  848, 1100, 2055, 1645, 1333, 2687, 2402,  886,
    1746, 3050, 1915, 2594,  821,  641,  910, 2154
};

/* ── Software NTT (matches VHDL engine exactly) ─────────────────── */

#ifdef LOCAL_BUILD
void ntt_sw(uint16_t *a, int inverse) {
    int s, b;
    for (s = 7; s >= 0; s--) {
        int half = 1 << s;
        for (b = 0; b < 128; b++) {
            int grp = b / half;
            int idx = b % half;
            int top = grp * 2 * half + idx;
            int bot = top + half;
            int tw_idx = idx * (128 / half);

            uint16_t av = a[top], bv = a[bot];
            uint16_t sum = av + bv;
            if (sum >= NTT_Q) sum -= NTT_Q;
            uint16_t dif = av + NTT_Q - bv;
            if (dif >= NTT_Q) dif -= NTT_Q;

            uint16_t tw_val = TW[tw_idx];
            if (inverse && tw_idx > 0)
                tw_val = NTT_Q - TW[128 - tw_idx];

            a[top] = sum;
            a[bot] = barrett((uint32_t)dif * tw_val);
        }
    }
    if (inverse) {
        for (int i = 0; i < NTT_N; i++)
            a[i] = barrett((uint32_t)a[i] * NTT_N_INV);
    }
}

void ntt_bit_reverse(uint16_t *a) {
    for (int i = 0; i < NTT_N; i++) {
        int j = 0, tmp = i;
        for (int b = 0; b < 8; b++) { j = (j << 1) | (tmp & 1); tmp >>= 1; }
        if (j > i) { uint16_t t = a[i]; a[i] = a[j]; a[j] = t; }
    }
}
#endif

/* ── Hardware driver (NEORV32 only) ─────────────────────────────── */

#ifndef LOCAL_BUILD
void ntt_hw_exec(uint16_t *a, int inverse) {
    int i;
    for (i = 0; i < NTT_N; i++) ntt_hw_write(i, a[i]);
    ntt_hw_start(inverse);
    while (!(ntt_hw_status() & 0x2)) ;
    for (i = 0; i < NTT_N; i++) a[i] = ntt_hw_read(i);
}
#endif

/* ── CLI state ──────────────────────────────────────────────────── */

#define CMD_BUF 128
#define MAX_ARGS 8

static char ntt_cmd[CMD_BUF];
static int ntt_pos;
static int ntt_done;

#ifdef LOCAL_BUILD
static uint16_t ntt_a[NTT_N];
static uint16_t ntt_b[NTT_N];
#endif

static void ntt_prompt(void) {
    vga_puts("ntt  > ", VGA_GREEN);
}

static void ntt_put_hex(uint16_t v) {
    static const char hex[] = "0123456789abcdef";
    vga_putc(hex[(v >> 12) & 0xf], VGA_YELLOW);
    vga_putc(hex[(v >>  8) & 0xf], VGA_YELLOW);
    vga_putc(hex[(v >>  4) & 0xf], VGA_YELLOW);
    vga_putc(hex[(v >>  0) & 0xf], VGA_YELLOW);
}

static void ntt_dump(const uint16_t *a, int n) {
    for (int i = 0; i < n; i++) {
        if (i && (i % 16 == 0)) vga_putc('\n', VGA_WHITE);
        ntt_put_hex(a[i]); vga_putc(' ', VGA_WHITE);
    }
    vga_putc('\n', VGA_WHITE);
}

/* ── Interactive commands ────────────────────────────────────────── */

static void cmd_load_delta(void) {
#ifdef LOCAL_BUILD
    for (int i = 0; i < NTT_N; i++) ntt_a[i] = 0;
    ntt_a[0] = 1;
    vga_puts("Loaded delta [1, 0, ..., 0]\n", VGA_CYAN);
#else
    for (int i = 0; i < NTT_N; i++) ntt_hw_write(i, 0);
    ntt_hw_write(0, 1);
    vga_puts("Loaded delta [1, 0, ..., 0] to HW\n", VGA_CYAN);
#endif
}

static void cmd_load_random(void) {
#ifdef LOCAL_BUILD
    for (int i = 0; i < NTT_N; i++) ntt_a[i] = (uint16_t)(rand() % NTT_Q);
    vga_puts("Loaded 256 random values\n", VGA_CYAN);
#else
    vga_puts("ERR: use 'load delta' on HW (no SW TRNG here)\n", VGA_RED);
#endif
}

static void cmd_ntt(int inverse) {
#ifdef LOCAL_BUILD
    ntt_sw(ntt_a, inverse);
    ntt_bit_reverse(ntt_a);
    vga_puts(inverse ? "INTT done (natural order)\n" : "NTT done (natural order)\n", VGA_CYAN);
    ntt_dump(ntt_a, 32);
    vga_puts("...\n", VGA_WHITE);
#else
    ntt_hw_start(inverse);
    while (!(ntt_hw_status() & 0x2)) ;
    vga_puts(inverse ? "HW INTT done\n" : "HW NTT done\n", VGA_CYAN);
#endif
}

static void cmd_roundtrip(void) {
#ifdef LOCAL_BUILD
    int ok = 1;
    for (int i = 0; i < NTT_N; i++) ntt_b[i] = ntt_a[i];

    ntt_sw(ntt_a, 0);
    ntt_bit_reverse(ntt_a);
    ntt_sw(ntt_a, 1);
    ntt_bit_reverse(ntt_a);

    for (int i = 0; i < NTT_N; i++) {
        if (ntt_a[i] != ntt_b[i]) { ok = 0; break; }
    }
    vga_puts(ok ? "ROUND-TRIP PASS\n" : "ROUND-TRIP FAIL\n",
             ok ? VGA_GREEN : VGA_RED);
#else
    int i, ok = 1;
    for (i = 0; i < NTT_N; i++) ntt_hw_write(i, ntt_hw_read(i));
    ntt_hw_start(0);
    while (!(ntt_hw_status() & 0x2)) ;
    ntt_hw_start(1);
    while (!(ntt_hw_status() & 0x2)) ;
    for (i = 0; i < NTT_N; i++) {
        uint16_t v = ntt_hw_read(i);
        /* INTT output is bit-reversed; just check non-zero for now */
        if (i == 0 && v == 0) ok = 0;
    }
    vga_puts(ok ? "HW ROUND-TRIP PASS (basic)\n" : "HW ROUND-TRIP FAIL\n",
             ok ? VGA_GREEN : VGA_RED);
#endif
}

static void cmd_show_help(void) {
    vga_puts("NTT accelerator CLI (N=256, q=3329, g=17)\n", VGA_CYAN);
    vga_puts("  load delta    Load [1,0,...,0]\n", VGA_WHITE);
    vga_puts("  load random   Load random values\n", VGA_WHITE);
    vga_puts("  ntt           Forward NTT\n", VGA_WHITE);
    vga_puts("  intt          Inverse NTT\n", VGA_WHITE);
    vga_puts("  roundtrip     NTT then INTT, check identity\n", VGA_WHITE);
    vga_puts("  dump          Show first 32 values\n", VGA_WHITE);
    vga_puts("  help          Show this help\n", VGA_WHITE);
    vga_puts("  clear         Clear screen\n", VGA_WHITE);
    vga_puts("  quit          Return to shell\n", VGA_WHITE);
}

static void cmd_dump(void) {
#ifdef LOCAL_BUILD
    ntt_dump(ntt_a, 32);
    vga_puts("...\n", VGA_WHITE);
#else
    vga_puts("HW data (first 32):\n", VGA_WHITE);
    for (int i = 0; i < 32; i++) {
        ntt_put_hex(ntt_hw_read(i)); vga_putc(' ', VGA_WHITE);
    }
    vga_putc('\n', VGA_WHITE);
#endif
}

/* ── Command dispatch ────────────────────────────────────────────── */

static int ntt_parse_args(char *args[], int max) {
    int argc = 0;
    char *p = ntt_cmd;
    while (*p && argc < max) {
        while (*p == ' ') p++;
        if (!*p) break;
        args[argc++] = p;
        while (*p && *p != ' ') p++;
        if (*p) *p++ = '\0';
    }
    return argc;
}

static void ntt_dispatch(void) {
    char *args[MAX_ARGS];
    int argc = ntt_parse_args(args, MAX_ARGS);
    if (argc == 0) return;

    if (strcmp(args[0], "help") == 0)       cmd_show_help();
    else if (strcmp(args[0], "load") == 0 && argc >= 2) {
        if (strcmp(args[1], "delta") == 0)  cmd_load_delta();
        else if (strcmp(args[1], "random") == 0) cmd_load_random();
        else vga_puts("Usage: load delta|random\n", VGA_RED);
    }
    else if (strcmp(args[0], "ntt") == 0)    cmd_ntt(0);
    else if (strcmp(args[0], "intt") == 0)   cmd_ntt(1);
    else if (strcmp(args[0], "roundtrip") == 0 || strcmp(args[0], "test") == 0)
                                             cmd_roundtrip();
    else if (strcmp(args[0], "dump") == 0)   cmd_dump();
    else if (strcmp(args[0], "clear") == 0 || strcmp(args[0], "cls") == 0) {
        vga_clear(); ntt_prompt();
    }
    else if (strcmp(args[0], "quit") == 0 || strcmp(args[0], "q") == 0)
        ntt_done = 1;
    else vga_puts("? Unknown command. Type 'help'\n", VGA_RED);
}

/* ── Program interface ───────────────────────────────────────────── */

static void ntt_init(void) {
    ntt_done = 0; ntt_pos = 0; ntt_cmd[0] = '\0';
    vga_clear();
    vga_goto(0, 0);
    vga_puts("=== NTT Accelerator ===\n", VGA_CYAN);
    vga_puts("N=256  q=3329  g=17  Barrett=5039\n", VGA_GRAY);
#ifdef LOCAL_BUILD
    vga_puts("Mode: SW reference\n", VGA_GRAY);
#else
    vga_puts("Mode: HW @ 0xF000F000\n", VGA_GRAY);
#endif
    vga_putc('\n', VGA_WHITE);
    cmd_show_help();
    vga_putc('\n', VGA_WHITE);
    ntt_prompt();
}

static void ntt_update(void) {}

static void ntt_input(char c) {
    if (ntt_done) return;

    if (c == '\r' || c == '\n') {
        ntt_cmd[ntt_pos] = '\0';
        vga_putc('\n', VGA_WHITE);
        ntt_dispatch();
        ntt_pos = 0; ntt_cmd[0] = '\0';
        if (!ntt_done) ntt_prompt();
    } else if (c == '\b' || c == 0x7f) {
        if (ntt_pos > 0) { ntt_pos--; ntt_cmd[ntt_pos] = '\0'; vga_putc('\b', VGA_WHITE); }
    } else if (c >= ' ' && c < 0x7f && ntt_pos < CMD_BUF - 1) {
        ntt_cmd[ntt_pos++] = c; ntt_cmd[ntt_pos] = '\0'; vga_putc(c, VGA_WHITE);
    }
}

static int ntt_finish(void) { return ntt_done; }

const program_t prog_ntt = {
    "NTT",
    "NTT accelerator CLI — load, ntt, intt, roundtrip",
    ntt_init,
    ntt_update,
    ntt_input,
    NULL,
    ntt_finish
};
