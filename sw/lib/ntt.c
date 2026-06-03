/* ntt.c — Software NTT + interactive CLI
 *
 * DIF Cooley-Tukey (A+B, (A-B)*w), stages 7→0, bit-reversed output.
 * Software bit-reversal for natural order.
 *
 * Hardware accelerator (ntt_sdf.vhd) removed from synthesis —
 * this module uses pure software NTT on both LOCAL and HW builds.
 */

#include "ntt.h"
#include "vga_hal.h"
#include "board_status.h"
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

#define NTT_PROG_ID 10u

static void ntt_put_hex(uint16_t v);

/* ── Barrett reduction (matches VHDL: constant=5039) ────────────── */

static inline uint16_t barrett(uint32_t x) {
    uint32_t q_est = (x * 5039u) >> 24;
    uint32_t r = x - q_est * 3329u;
    if (r >= 3329u) r -= 3329u;
    return (uint16_t)r;
}

/* ── Twiddle table ──────────────────────────────────────────── */
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

/* ── Software NTT ──────────────────────────────────────────────── */

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

/* ── CLI state ──────────────────────────────────────────────────── */

#define CMD_BUF 128
#define MAX_ARGS 8

static char ntt_cmd[CMD_BUF];
static int ntt_pos;
static int ntt_done;

static uint16_t ntt_a[NTT_N];
static uint16_t ntt_b[NTT_N];

static void ntt_prompt(void) {
    vga_puts("ntt > ", VGA_GREEN);
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
    for (int i = 0; i < NTT_N; i++) ntt_a[i] = 0;
    ntt_a[0] = 1;
    vga_puts("Loaded delta [1, 0, ..., 0]\n", VGA_CYAN);
}

#ifdef LOCAL_BUILD
static void cmd_load_random(void) {
    for (int i = 0; i < NTT_N; i++) ntt_a[i] = (uint16_t)(rand() % NTT_Q);
    vga_puts("Loaded 256 random values\n", VGA_CYAN);
}
#endif

static void cmd_ntt(int inverse) {
    ntt_sw(ntt_a, inverse);
    ntt_bit_reverse(ntt_a);
    vga_puts(inverse ? "INTT done (natural order)\n" : "NTT done (natural order)\n", VGA_CYAN);
    ntt_dump(ntt_a, 32);
    vga_puts("...\n", VGA_WHITE);
}

static void cmd_roundtrip(void) {
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
}

static void cmd_show_help(void) {
    vga_puts("NTT: Number Theoretic Transform\n", VGA_CYAN);
    vga_puts("  N=256  q=3329  generator=17\n", VGA_GRAY);
    vga_puts("  (SW only — HW accelerator removed)\n", VGA_GRAY);
    vga_puts("Commands:\n", VGA_WHITE);
    vga_puts("  load delta    Delta input [1,0,...,0]\n", VGA_WHITE);
#ifdef LOCAL_BUILD
    vga_puts("  load random   Random coefficients\n", VGA_WHITE);
#endif
    vga_puts("  ntt           Forward NTT\n", VGA_WHITE);
    vga_puts("  intt          Inverse NTT\n", VGA_WHITE);
    vga_puts("  roundtrip     NTT+INTT, verify identity\n", VGA_WHITE);
    vga_puts("  dump          Show first 32 values\n", VGA_WHITE);
    vga_puts("  clear (cls)   Clear screen\n", VGA_GRAY);
    vga_puts("  quit (q)      Return to shell\n", VGA_GRAY);
}

static void cmd_dump(void) {
    ntt_dump(ntt_a, 32);
    vga_puts("...\n", VGA_WHITE);
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
#ifdef LOCAL_BUILD
        else if (strcmp(args[1], "random") == 0) cmd_load_random();
#endif
        else vga_puts("Usage: load delta\n", VGA_RED);
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
    board_status_set_program(NTT_PROG_ID, BOARD_STATE_RUN, 0u, 0u);
    vga_clear();
    vga_goto(0, 0);
    vga_puts("=== NTT (Software) ===\n", VGA_CYAN);
    vga_puts("N=256  q=3329  g=17  Barrett=5039\n", VGA_GRAY);
    vga_puts("Mode: SW reference (~0.4ms)\n", VGA_GRAY);
    vga_putc('\n', VGA_WHITE);
    vga_puts("Type 'help' for commands\n", VGA_GRAY);
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
    "Software NTT — load, ntt, intt, roundtrip",
    ntt_init,
    ntt_update,
    ntt_input,
    NULL,
    ntt_finish,
    PROG_FLAG_CLI
};
