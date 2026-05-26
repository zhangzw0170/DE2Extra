#include "vga_hal.h"
#include "crypto.h"

#include <stdint.h>

#ifdef LOCAL_BUILD
  #include <string.h>
  #include <time.h>
#else
  static int strcmp(const char *a, const char *b) {
      while (*a && *a == *b) {
          a++;
          b++;
      }
      return (unsigned char)*a - (unsigned char)*b;
  }
#endif

#define CMD_BUF_SIZE 128
#define MAX_ARGS 8
#define HISTORY_DEPTH 4

static char cmd_buf[CMD_BUF_SIZE];
static int cmd_pos;
static int done;
static char saved_cmd[CMD_BUF_SIZE];
static char cmd_history[HISTORY_DEPTH][CMD_BUF_SIZE];
static int cmd_history_count;
static int cmd_history_nav;
static int esc_state;

static void put_dec(unsigned value, uint16_t color) {
    char buf[10];
    int pos = 0;

    if (value == 0u) {
        vga_putc('0', color);
        return;
    }

    while ((value != 0u) && (pos < (int)sizeof(buf))) {
        buf[pos++] = (char)('0' + (value % 10u));
        value /= 10u;
    }

    while (pos > 0) {
        vga_putc(buf[--pos], color);
    }
}

static void put_dec_padded(unsigned value, unsigned width, uint16_t color) {
    char buf[10];
    unsigned pos = 0;

    do {
        buf[pos++] = (char)('0' + (value % 10u));
        value /= 10u;
    } while ((value != 0u) && (pos < (unsigned)sizeof(buf)));

    while (pos < width && pos < (unsigned)sizeof(buf)) {
        buf[pos++] = '0';
    }

    while (pos > 0u) {
        vga_putc(buf[--pos], color);
    }
}

static void put_hex32(uint32_t val, uint16_t color) {
    static const char hex[] = "0123456789abcdef";
    for (int i = 7; i >= 0; i--) {
        vga_putc(hex[(val >> (i * 4)) & 0x0f], color);
    }
}

static void put_hex_buf(const uint8_t *data, int len, uint16_t color) {
    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < len; i++) {
        vga_putc(hex[data[i] >> 4], color);
        vga_putc(hex[data[i] & 0x0f], color);
    }
}

void hex_print(const uint8_t *data, int len) {
    put_hex_buf(data, len, VGA_YELLOW);
}

int hex_decode(const char *hex, uint8_t *out, int max_len) {
    int len = 0;

    while (*hex && len < max_len) {
        int hi = -1;
        int lo = -1;

        while ((*hex == ' ') || (*hex == '\t')) {
            hex++;
        }
        if (*hex == '\0') {
            break;
        }

        if ((hex[0] >= '0') && (hex[0] <= '9')) hi = hex[0] - '0';
        else if ((hex[0] >= 'a') && (hex[0] <= 'f')) hi = hex[0] - 'a' + 10;
        else if ((hex[0] >= 'A') && (hex[0] <= 'F')) hi = hex[0] - 'A' + 10;

        if ((hex[1] >= '0') && (hex[1] <= '9')) lo = hex[1] - '0';
        else if ((hex[1] >= 'a') && (hex[1] <= 'f')) lo = hex[1] - 'a' + 10;
        else if ((hex[1] >= 'A') && (hex[1] <= 'F')) lo = hex[1] - 'A' + 10;

        if ((hi < 0) || (lo < 0)) {
            return -1;
        }

        out[len++] = (uint8_t)((hi << 4) | lo);
        hex += 2;
    }

    return len;
}

static int parse_args(char *args[], int max_args) {
    int argc = 0;
    char *p = cmd_buf;

    while (*p && (argc < max_args)) {
        while ((*p == ' ') || (*p == '\t')) {
            p++;
        }
        if (*p == '\0') {
            break;
        }

        args[argc++] = p;
        while (*p && (*p != ' ') && (*p != '\t')) {
            p++;
        }
        if (*p) {
            *p = '\0';
            p++;
        }
    }

    return argc;
}

static int parse_u32_dec(const char *s) {
    int n = 0;

    if (*s == '\0') {
        return -1;
    }

    while (*s) {
        if ((*s < '0') || (*s > '9')) {
            return -1;
        }
        n = (n * 10) + (*s - '0');
        s++;
    }

    return n;
}

#ifdef LOCAL_BUILD
static uint32_t trng_state = 0x13579BDFu;
static clock_t bench_start;

void trng_init(void) {
    trng_state = (uint32_t)time(NULL) ^ 0x2468ACE0u;
}

void trng_bytes(uint8_t *buf, int n) {
    for (int i = 0; i < n; i++) {
        trng_state = trng_state * 1103515245u + 12345u;
        buf[i] = (uint8_t)(trng_state >> 16);
    }
}

int trng_available(void) {
    return 1;
}

void bench_reset(void) {
    bench_start = clock();
}

uint32_t bench_cycles(void) {
    clock_t now = clock();
    return (uint32_t)((now - bench_start) * 1000000 / CLOCKS_PER_SEC);
}
#else
static uint64_t bench_start;

static void bench_reset_now(void) {
    bench_start = neorv32_cpu_get_cycle();
}

static uint32_t bench_cycles_now(void) {
    return (uint32_t)(neorv32_cpu_get_cycle() - bench_start);
}

void trng_bytes(uint8_t *buf, int n) {
    for (int i = 0; i < n; i++) {
        while (!neorv32_trng_data_avail());
        buf[i] = neorv32_trng_data_get();
    }
}
#endif

static void prompt(void) {
    vga_puts("crypto  > ", VGA_GREEN);
}

static void redraw_input_line(int old_len) {
    vga_putc('\r', VGA_WHITE);
    prompt();
    for (int i = 0; i < cmd_pos; i++) {
        vga_putc(cmd_buf[i], VGA_WHITE);
    }
    for (int i = cmd_pos; i < old_len; i++) {
        vga_putc(' ', VGA_WHITE);
    }
    vga_putc('\r', VGA_WHITE);
    prompt();
    for (int i = 0; i < cmd_pos; i++) {
        vga_putc(cmd_buf[i], VGA_WHITE);
    }
}

static void history_store_current(void) {
    for (int i = 0; i <= cmd_pos; i++) {
        saved_cmd[i] = cmd_buf[i];
    }
}

static void history_load(const char *src) {
    int i = 0;
    while (src[i] && i < CMD_BUF_SIZE - 1) {
        cmd_buf[i] = src[i];
        i++;
    }
    cmd_buf[i] = '\0';
    cmd_pos = i;
}

static void history_push(void) {
    if (cmd_pos == 0) {
        return;
    }
    if ((cmd_history_count > 0) && (strcmp(cmd_history[cmd_history_count - 1], cmd_buf) == 0)) {
        return;
    }
    if (cmd_history_count < HISTORY_DEPTH) {
        for (int i = 0; i <= cmd_pos; i++) {
            cmd_history[cmd_history_count][i] = cmd_buf[i];
        }
        cmd_history_count++;
    } else {
        for (int i = 1; i < HISTORY_DEPTH; i++) {
            for (int j = 0; j < CMD_BUF_SIZE; j++) {
                cmd_history[i - 1][j] = cmd_history[i][j];
            }
        }
        for (int i = 0; i <= cmd_pos; i++) {
            cmd_history[HISTORY_DEPTH - 1][i] = cmd_buf[i];
        }
    }
}

static void history_prev(void) {
    int old_len = cmd_pos;
    if (cmd_history_count <= 0) {
        return;
    }
    if (cmd_history_nav < 0) {
        history_store_current();
        cmd_history_nav = cmd_history_count - 1;
    } else if (cmd_history_nav > 0) {
        cmd_history_nav--;
    } else {
        return;
    }
    history_load(cmd_history[cmd_history_nav]);
    redraw_input_line(old_len);
}

static void history_next(void) {
    int old_len = cmd_pos;
    if (cmd_history_nav < 0) {
        return;
    }
    if (cmd_history_nav < (cmd_history_count - 1)) {
        cmd_history_nav++;
        history_load(cmd_history[cmd_history_nav]);
    } else {
        cmd_history_nav = -1;
        history_load(saved_cmd);
    }
    redraw_input_line(old_len);
}

static void draw_page(void) {
    vga_clear();
    vga_goto(0, 0);
    vga_puts("DE2Extra Crypto CLI\n", VGA_CYAN);
    vga_puts("Commands: help info aes sha256 sha512 sm4 sm3 trng\n", VGA_GRAY);
    vga_puts("          bench clear quit\n", VGA_GRAY);
    vga_puts("ISA: RV32IMC + Zicsr + Zicntr + Zifencei\n", VGA_GRAY);
    vga_puts("     Zbkb + Zbkc + Zbkx + Zkne + Zknd + Zknh + Zksed + Zksh\n\n", VGA_GRAY);
}

static void redraw(void) {
    draw_page();
    prompt();
}

static void ensure_lines_available(int lines) {
    if ((vga_row() + lines) >= (VGA_ROWS - 1)) {
        draw_page();
    }
}

static void show_info(void) {
    ensure_lines_available(6);
    vga_puts("Target: NEORV32 RISC-V @ 50 MHz\n", VGA_WHITE);
    vga_puts("ISA:    RV32IMC + Zicsr + Zicntr + Zifencei\n", VGA_WHITE);
    vga_puts("        Zbkb + Zbkc + Zbkx + Zkne + Zknd + Zknh + Zksed + Zksh\n", VGA_WHITE);
    vga_puts("Memory: IMEM 16KB, DMEM 16KB\n", VGA_WHITE);
    vga_puts("Build:  " __DATE__ " " __TIME__ "\n", VGA_WHITE);
#ifdef LOCAL_BUILD
    vga_puts("Mode:   LOCAL_BUILD\n", VGA_WHITE);
#else
    vga_puts("Mode:   NEORV32\n", VGA_WHITE);
#endif
}

static void show_help(void) {
    ensure_lines_available(12);
    vga_puts("  help                              Show help\n", VGA_WHITE);
    vga_puts("  info                              Show system information\n", VGA_WHITE);
    vga_puts("  aes enc <key> <pt>                AES-128 ECB encrypt\n", VGA_WHITE);
    vga_puts("  aes dec <key> <ct>                AES-128 ECB decrypt\n", VGA_WHITE);
    vga_puts("  sha256 <hex-msg>                  SHA-256 hash\n", VGA_WHITE);
    vga_puts("  sha512 <hex-msg>                  SHA-512 hash\n", VGA_WHITE);
    vga_puts("  sm4 enc <key> <pt>                SM4 encrypt\n", VGA_WHITE);
    vga_puts("  sm3 <hex-msg>                     SM3 hash\n", VGA_WHITE);
    vga_puts("  trng [n]                          Read n random bytes\n", VGA_WHITE);
    vga_puts("  bench                             Run software / Zk* benchmark + TRNG stats\n", VGA_WHITE);
    vga_puts("  clear                             Clear this program screen\n", VGA_WHITE);
    vga_puts("  quit                              Return to shell\n", VGA_WHITE);
}

static int cmd_aes(int argc, char *args[]) {
    uint8_t key[16];
    uint8_t data[16];
    uint8_t out[16];
    uint32_t rk[44];
    int is_enc;

    if (argc < 4) {
        vga_puts("Usage: aes enc <key> <pt> | aes dec <key> <ct>\n", VGA_RED);
        return -1;
    }

    if (strcmp(args[1], "enc") == 0) is_enc = 1;
    else if (strcmp(args[1], "dec") == 0) is_enc = 0;
    else {
        vga_puts("ERR: expected 'enc' or 'dec'\n", VGA_RED);
        return -1;
    }

    if (hex_decode(args[2], key, 16) != 16) {
        vga_puts("ERR: key must be 16 bytes (32 hex chars)\n", VGA_RED);
        return -1;
    }
    if (hex_decode(args[3], data, 16) != 16) {
        vga_puts("ERR: data must be 16 bytes (32 hex chars)\n", VGA_RED);
        return -1;
    }

    aes128_key_expand(key, rk);
    if (is_enc) {
        aes128_enc_block(data, rk, out);
    } else {
        aes128_dec_block(data, rk, out);
    }

    put_hex_buf(out, 16, VGA_YELLOW);
    vga_putc('\n', VGA_WHITE);
    return 0;
}

static int cmd_sha256_hash(int argc, char *args[]) {
    uint8_t msg[1024];
    uint8_t digest[32];
    int len;

    if (argc < 2) {
        vga_puts("Usage: sha256 <hex-msg>\n", VGA_RED);
        return -1;
    }

    len = hex_decode(args[1], msg, sizeof(msg));
    if (len < 0) {
        vga_puts("ERR: invalid hex input\n", VGA_RED);
        return -1;
    }

    sha256_hash(msg, (size_t)len, digest);
    put_hex_buf(digest, 32, VGA_YELLOW);
    vga_putc('\n', VGA_WHITE);
    return 0;
}

static int cmd_sha512_hash(int argc, char *args[]) {
    uint8_t msg[1024];
    uint8_t digest[64];
    int len;

    if (argc < 2) {
        vga_puts("Usage: sha512 <hex-msg>\n", VGA_RED);
        return -1;
    }

    len = hex_decode(args[1], msg, sizeof(msg));
    if (len < 0) {
        vga_puts("ERR: invalid hex input\n", VGA_RED);
        return -1;
    }

    sha512_hash(msg, (size_t)len, digest);
    put_hex_buf(digest, 64, VGA_YELLOW);
    vga_putc('\n', VGA_WHITE);
    return 0;
}

static int cmd_sm4(int argc, char *args[]) {
    uint8_t key[16];
    uint8_t data[16];
    uint8_t out[16];
    uint32_t rk[32];

    if (argc < 4) {
        vga_puts("Usage: sm4 enc <key> <pt>\n", VGA_RED);
        return -1;
    }
    if (strcmp(args[1], "enc") != 0) {
        vga_puts("ERR: only 'sm4 enc' is wired in this shell build\n", VGA_RED);
        return -1;
    }
    if (hex_decode(args[2], key, 16) != 16) {
        vga_puts("ERR: key must be 16 bytes (32 hex chars)\n", VGA_RED);
        return -1;
    }
    if (hex_decode(args[3], data, 16) != 16) {
        vga_puts("ERR: data must be 16 bytes (32 hex chars)\n", VGA_RED);
        return -1;
    }

    sm4_key_schedule(key, rk);
    sm4_encrypt(data, rk, out);
    put_hex_buf(out, 16, VGA_YELLOW);
    vga_putc('\n', VGA_WHITE);
    return 0;
}

static int cmd_sm3_hash(int argc, char *args[]) {
    uint8_t msg[1024];
    uint8_t digest[32];
    int len;

    if (argc < 2) {
        vga_puts("Usage: sm3 <hex-msg>\n", VGA_RED);
        return -1;
    }

    len = hex_decode(args[1], msg, sizeof(msg));
    if (len < 0) {
        vga_puts("ERR: invalid hex input\n", VGA_RED);
        return -1;
    }

    sm3_hash(msg, (size_t)len, digest);
    put_hex_buf(digest, 32, VGA_YELLOW);
    vga_putc('\n', VGA_WHITE);
    return 0;
}

static int cmd_trng_read(int argc, char *args[]) {
    uint8_t buf[256];
    int n = 16;

    if (argc >= 2) {
        n = parse_u32_dec(args[1]);
        if ((n <= 0) || (n > (int)sizeof(buf))) {
            vga_puts("ERR: n must be 1..256\n", VGA_RED);
            return -1;
        }
    }

#ifndef LOCAL_BUILD
    if (!trng_available()) {
        vga_puts("ERR: hardware TRNG not available\n", VGA_RED);
        return -1;
    }
#endif

    trng_bytes(buf, n);
    put_hex_buf(buf, n, VGA_YELLOW);
    vga_putc('\n', VGA_WHITE);
    return 0;
}

#ifndef LOCAL_BUILD
static void bench_print_line(const char *label, uint32_t sw_cycles, uint32_t hw_cycles) {
    vga_puts(label, VGA_WHITE);
    while (vga_col() < 14) {
        vga_putc(' ', VGA_WHITE);
    }
    put_hex32(sw_cycles, VGA_YELLOW);
    vga_puts("  ", VGA_WHITE);
    put_hex32(hw_cycles, VGA_CYAN);
    vga_puts("  ", VGA_WHITE);
    if (hw_cycles != 0u) {
        uint32_t whole = (sw_cycles * 10u) / hw_cycles;
        put_dec(whole / 10u, VGA_GREEN);
        vga_putc('.', VGA_GREEN);
        put_dec(whole % 10u, VGA_GREEN);
        vga_putc('x', VGA_GREEN);
    } else {
        vga_puts("--", VGA_RED);
    }
    vga_putc('\n', VGA_WHITE);
}
#endif

static int cmd_bench(void) {
    uint8_t key[16];
    uint8_t pt[16];
    uint8_t ct[16];
    uint8_t msg[64];
    uint8_t digest[64];
    uint8_t trng_buf[256];
    uint32_t rk_aes[44];
    uint32_t rk_sm4[32];
    uint32_t t_aes;
    uint32_t t_sha256;
    uint32_t t_sha512;
    uint32_t t_sm4;
    uint32_t t_sm3;
    uint32_t trng_ones = 0;
    int i;

#ifdef LOCAL_BUILD
    enum { bench_iters = 1000 };
    bench_reset();
#else
    enum { bench_iters = 1000 };
    bench_reset_now();
#endif

    for (i = 0; i < 16; i++) {
        key[i] = (uint8_t)i;
        pt[i] = (uint8_t)(0x10 + i);
    }
    for (i = 0; i < 64; i++) {
        msg[i] = (uint8_t)i;
    }

    aes128_key_expand(key, rk_aes);
    for (i = 0; i < bench_iters; i++) {
        aes128_enc_block(pt, rk_aes, ct);
    }
#ifdef LOCAL_BUILD
    t_aes = bench_cycles();
    bench_reset();
#else
    t_aes = bench_cycles_now();
    bench_reset_now();
#endif

    for (i = 0; i < bench_iters; i++) {
        sha256_hash(msg, 64u, digest);
    }
#ifdef LOCAL_BUILD
    t_sha256 = bench_cycles();
    bench_reset();
#else
    t_sha256 = bench_cycles_now();
    bench_reset_now();
#endif

    for (i = 0; i < bench_iters; i++) {
        sha512_hash(msg, 64u, digest);
    }
#ifdef LOCAL_BUILD
    t_sha512 = bench_cycles();
    bench_reset();
#else
    t_sha512 = bench_cycles_now();
    bench_reset_now();
#endif

    sm4_key_schedule(key, rk_sm4);
    for (i = 0; i < bench_iters; i++) {
        sm4_encrypt(pt, rk_sm4, ct);
    }
#ifdef LOCAL_BUILD
    t_sm4 = bench_cycles();
    bench_reset();
#else
    t_sm4 = bench_cycles_now();
    bench_reset_now();
#endif

    for (i = 0; i < bench_iters; i++) {
        sm3_hash(msg, 64u, digest);
    }
#ifdef LOCAL_BUILD
    t_sm3 = bench_cycles();
#else
    t_sm3 = bench_cycles_now();
#endif

    ensure_lines_available(17);
    vga_puts("Software benchmark\n", VGA_CYAN);
    vga_puts("AES-128 enc  x", VGA_WHITE);
    put_dec((unsigned)bench_iters, VGA_YELLOW);
    vga_puts(": ", VGA_WHITE);
    put_hex32(t_aes, VGA_YELLOW);
    vga_putc('\n', VGA_WHITE);
    vga_puts("SHA-256      x", VGA_WHITE);
    put_dec((unsigned)bench_iters, VGA_YELLOW);
    vga_puts(": ", VGA_WHITE);
    put_hex32(t_sha256, VGA_YELLOW);
    vga_putc('\n', VGA_WHITE);
    vga_puts("SHA-512      x", VGA_WHITE);
    put_dec((unsigned)bench_iters, VGA_YELLOW);
    vga_puts(": ", VGA_WHITE);
    put_hex32(t_sha512, VGA_YELLOW);
    vga_putc('\n', VGA_WHITE);
    vga_puts("SM4 enc      x", VGA_WHITE);
    put_dec((unsigned)bench_iters, VGA_YELLOW);
    vga_puts(": ", VGA_WHITE);
    put_hex32(t_sm4, VGA_YELLOW);
    vga_putc('\n', VGA_WHITE);
    vga_puts("SM3          x", VGA_WHITE);
    put_dec((unsigned)bench_iters, VGA_YELLOW);
    vga_puts(": ", VGA_WHITE);
    put_hex32(t_sm3, VGA_YELLOW);
    vga_putc('\n', VGA_WHITE);

#ifndef LOCAL_BUILD
    {
        uint32_t rk_zkn[44];
        uint32_t rk_zks[32];
        uint32_t t_zkn_aes;
        uint32_t t_zkn_sha256;
        uint32_t t_zkn_sha512;
        uint32_t t_zks_sm4;
        uint32_t t_zks_sm3;

        bench_reset_now();
        aes128_key_expand_zkn(key, rk_zkn);
        for (i = 0; i < bench_iters; i++) {
            aes128_enc_block_zkn(pt, rk_zkn, ct);
        }
        t_zkn_aes = bench_cycles_now();

        bench_reset_now();
        for (i = 0; i < bench_iters; i++) {
            sha256_hash_zkn(msg, 64u, digest);
        }
        t_zkn_sha256 = bench_cycles_now();

        bench_reset_now();
        for (i = 0; i < bench_iters; i++) {
            sha512_hash_zkn(msg, 64u, digest);
        }
        t_zkn_sha512 = bench_cycles_now();

        bench_reset_now();
        sm4_key_schedule_zks(key, rk_zks);
        for (i = 0; i < bench_iters; i++) {
            sm4_encrypt_zks(pt, rk_zks, ct);
        }
        t_zks_sm4 = bench_cycles_now();

        bench_reset_now();
        for (i = 0; i < bench_iters; i++) {
            sm3_hash_zks(msg, 64u, digest);
        }
        t_zks_sm3 = bench_cycles_now();

        vga_puts("Zk* acceleration\n", VGA_CYAN);
        vga_puts("Label          SW        Zk*       Speedup\n", VGA_WHITE);
        bench_print_line("AES-128 enc", t_aes, t_zkn_aes);
        bench_print_line("SHA-256", t_sha256, t_zkn_sha256);
        bench_print_line("SHA-512", t_sha512, t_zkn_sha512);
        bench_print_line("SM4 enc", t_sm4, t_zks_sm4);
        bench_print_line("SM3", t_sm3, t_zks_sm3);
    }
#endif

    vga_puts("TRNG statistics (256 bytes)\n", VGA_CYAN);
    trng_bytes(trng_buf, (int)sizeof(trng_buf));
    for (i = 0; i < (int)sizeof(trng_buf); i++) {
        uint8_t b = trng_buf[i];
        while (b != 0u) {
            trng_ones += (uint32_t)(b & 1u);
            b >>= 1;
        }
    }
    vga_puts("Total bits : 2048\n", VGA_WHITE);
    vga_puts("1-bits/0-bits : ", VGA_WHITE);
    put_dec(trng_ones, VGA_YELLOW);
    vga_puts(" / ", VGA_WHITE);
    put_dec(2048u - trng_ones, VGA_YELLOW);
    vga_putc('\n', VGA_WHITE);
    vga_puts("One ratio  : ", VGA_WHITE);
    {
        uint32_t ratio_bp = (trng_ones * 10000u) / 2048u;
        put_dec(ratio_bp / 100u, VGA_YELLOW);
        vga_putc('.', VGA_WHITE);
        put_dec_padded(ratio_bp % 100u, 2u, VGA_YELLOW);
    }
    vga_puts("%\n", VGA_WHITE);

    return 0;
}

static int dispatch(int argc, char *args[], int *printed_prompt) {
    char *cmd;

    *printed_prompt = 0;
    if (argc == 0) {
        return 0;
    }

    cmd = args[0];
    if ((strcmp(cmd, "help") == 0) || (strcmp(cmd, "?") == 0)) {
        show_help();
        return 0;
    }
    if (strcmp(cmd, "info") == 0) {
        show_info();
        return 0;
    }
    if ((strcmp(cmd, "clear") == 0) || (strcmp(cmd, "cls") == 0)) {
        redraw();
        *printed_prompt = 1;
        return 0;
    }
    if ((strcmp(cmd, "quit") == 0) || (strcmp(cmd, "exit") == 0) || (strcmp(cmd, "q") == 0)) {
        done = 1;
        return 0;
    }
    if (strcmp(cmd, "aes") == 0) {
        return cmd_aes(argc, args);
    }
    if (strcmp(cmd, "sha256") == 0) {
        return cmd_sha256_hash(argc, args);
    }
    if (strcmp(cmd, "sha512") == 0) {
        return cmd_sha512_hash(argc, args);
    }
    if (strcmp(cmd, "sm4") == 0) {
        return cmd_sm4(argc, args);
    }
    if (strcmp(cmd, "sm3") == 0) {
        return cmd_sm3_hash(argc, args);
    }
    if (strcmp(cmd, "trng") == 0) {
        return cmd_trng_read(argc, args);
    }
    if (strcmp(cmd, "bench") == 0) {
        return cmd_bench();
    }

    vga_puts("ERR: unknown command\n", VGA_RED);
    return -1;
}

static void init(void) {
    done = 0;
    cmd_pos = 0;
    cmd_buf[0] = '\0';
    saved_cmd[0] = '\0';
    cmd_history_nav = -1;
    esc_state = 0;
    trng_init();
    redraw();
}

static void update(void) {}

static void input(char c) {
    int printed_prompt = 0;

    if (done) {
        return;
    }

    if (esc_state == 1) {
        esc_state = (c == '[') ? 2 : 0;
        return;
    }
    if (esc_state == 2) {
        if (c == 'A') {
            history_prev();
        } else if (c == 'B') {
            history_next();
        }
        esc_state = 0;
        return;
    }
    if (c == 27) {
        esc_state = 1;
        return;
    }

    if ((c == '\r') || (c == '\n')) {
        char *args[MAX_ARGS];
        int argc;

        cmd_buf[cmd_pos] = '\0';
        vga_putc('\n', VGA_WHITE);
        ensure_lines_available(1);
        if (cmd_pos > 0) {
            history_push();
        }
        cmd_history_nav = -1;
        saved_cmd[0] = '\0';
        argc = parse_args(args, MAX_ARGS);
        (void)dispatch(argc, args, &printed_prompt);
        cmd_pos = 0;
        cmd_buf[0] = '\0';
        if (!done && !printed_prompt) {
            ensure_lines_available(1);
            prompt();
        }
        return;
    }

    if ((c == '\b') || (c == 0x7f)) {
        if (cmd_pos > 0) {
            cmd_pos--;
            cmd_buf[cmd_pos] = '\0';
            vga_putc('\b', VGA_WHITE);
        }
        return;
    }

    if ((c >= 0x20) && (c < 0x7f) && (cmd_pos < CMD_BUF_SIZE - 1)) {
        cmd_buf[cmd_pos++] = c;
        cmd_buf[cmd_pos] = '\0';
        vga_putc(c, VGA_WHITE);
    }
}

static int finish(void) {
    return done;
}

const program_t prog_crypto = {
    "Crypto",
    "Crypto CLI — AES/SHA/SM4/SM3/TRNG/bench",
    init,
    update,
    input,
    NULL,
    finish
};
