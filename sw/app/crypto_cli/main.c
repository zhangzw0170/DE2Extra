/*
 * main.c — Phase 2a Crypto CLI: command parser and entry point
 *
 * Dual-mode: LOCAL_BUILD (stdin/stdout) vs NEORV32 bare-metal (UART).
 * Compile (local):  gcc -DLOCAL_BUILD -o crypto_cli *.c
 * Compile (NEORV32): via sw/build.sh app/crypto_cli
 */

#include "crypto.h"

#ifdef LOCAL_BUILD
  #include <stdio.h>
  #include <stdlib.h>
  #include <string.h>
  #include <time.h>
#else
  #include <neorv32.h>
  #define BAUD_RATE 115200
  #define LCD_STATUS_CRYPTO 0x20000000u

  /* Bare-metal strcmp (NEORV32 has no libc string.h) */
  static int strcmp(const char *a, const char *b) {
      while (*a && *a == *b) { a++; b++; }
      return (unsigned char)*a - (unsigned char)*b;
  }

  static void board_set_status(uint32_t status) {
      uint32_t gpio = neorv32_gpio_port_get();
      gpio = (gpio & 0x0FFFFFFFu) | status;
      neorv32_gpio_port_set(gpio);
  }
#endif

/* ── I/O abstraction ──────────────────────────────────────────── */

#ifdef LOCAL_BUILD
  static void io_putc(char c)     { putchar(c); }
  static void io_puts(const char *s) { printf("%s", s); }
  static int io_getc(void)        { return getchar(); }
  static void io_flush(void)      { fflush(stdout); }
#else
  static void io_putc(char c)     { neorv32_uart0_putc(c); }
  static void io_puts(const char *s) { neorv32_uart0_puts(s); }
  static int io_getc(void)        { return (unsigned char)neorv32_uart0_getc(); }
  static void io_flush(void)      { /* UART is unbuffered */ }
#endif

/* ── Utility ──────────────────────────────────────────────────── */

#define CMD_BUF_SIZE  256
#define MAX_ARGS       8

static char    cmd_buf[CMD_BUF_SIZE];
static int     cmd_pos;
static int     cmd_last = 0;          /* last command return code */

/* Print 32-bit value as 8 hex digits */
static void put_hex32(uint32_t val) {
    static const char hex[] = "0123456789abcdef";
    for (int i = 7; i >= 0; i--) {
        io_putc(hex[(val >> (i * 4)) & 0xF]);
    }
}

/* Print byte buffer as hex string */
void hex_print(const uint8_t *data, int len) {
    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < len; i++) {
        io_putc(hex[data[i] >> 4]);
        io_putc(hex[data[i] & 0xF]);
    }
}

/* Print byte buffer as hex string (internal, same as hex_print) */
static void put_hex_buf(const uint8_t *data, int len) {
    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < len; i++) {
        io_putc(hex[data[i] >> 4]);
        io_putc(hex[data[i] & 0xF]);
    }
}

/* Decode hex string to byte buffer. Returns byte count or -1 on error. */
int hex_decode(const char *hex, uint8_t *out, int max_len) {
    int len = 0;
    while (*hex && len < max_len) {
        /* skip whitespace */
        while (*hex == ' ' || *hex == '\t') hex++;
        if (!*hex) break;

        /* need two hex digits */
        if (!hex[0] || !hex[1]) return -1;
        char c1 = hex[0], c2 = hex[1];

        int v1 = -1, v2 = -1;
        if (c1 >= '0' && c1 <= '9') v1 = c1 - '0';
        else if (c1 >= 'a' && c1 <= 'f') v1 = c1 - 'a' + 10;
        else if (c1 >= 'A' && c1 <= 'F') v1 = c1 - 'A' + 10;
        else return -1;

        if (c2 >= '0' && c2 <= '9') v2 = c2 - '0';
        else if (c2 >= 'a' && c2 <= 'f') v2 = c2 - 'a' + 10;
        else if (c2 >= 'A' && c2 <= 'F') v2 = c2 - 'A' + 10;
        else return -1;

        out[len++] = (uint8_t)((v1 << 4) | v2);
        hex += 2;
    }
    return len;
}

/* Read a line from input */
static int read_line(void) {
    cmd_pos = 0;
    while (1) {
        int c = io_getc();
        if (c < 0) {
#ifdef LOCAL_BUILD
            if (cmd_pos == 0) {
                return 0;
            }
            cmd_buf[cmd_pos] = '\0';
            return cmd_pos;
#else
            continue;
#endif
        }
        if (c == '\r' || c == '\n') {
            io_puts("\n");
            cmd_buf[cmd_pos] = '\0';
            return cmd_pos;
        }
        if (c == '\b' || c == 0x7F) { /* backspace */
            if (cmd_pos > 0) {
                cmd_pos--;
                io_puts("\b \b");
            }
            continue;
        }
        if (c >= 0x20 && c < 0x7F && cmd_pos < CMD_BUF_SIZE - 1) {
            cmd_buf[cmd_pos++] = c;
            io_putc(c);
            io_flush();
        }
    }
}

/* Parse cmd_buf into argc/argv. Modifies cmd_buf in-place. */
static int parse_args(char *args[], int max_args) {
    int argc = 0;
    char *p = cmd_buf;

    while (*p && argc < max_args) {
        /* skip leading whitespace */
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;

        args[argc++] = p;

        /* scan to end of token */
        while (*p && *p != ' ' && *p != '\t') p++;
        if (*p) {
            *p = '\0';
            p++;
        }
    }
    return argc;
}

/* Print a digest / block with label */
static void print_digest(const char *label, const uint8_t *data, int len) {
    io_puts(label);
    put_hex_buf(data, len);
    io_puts("\n");
}

/* ── TRNG (local LCG stub) ────────────────────────────────────── */

#ifdef LOCAL_BUILD
static uint32_t trng_state = 0xDEADBEEF;

void trng_init(void) {
    trng_state = (uint32_t)time(NULL) ^ 0x12345678;
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
#else
/* NEORV32: use hardware TRNG */
void trng_bytes(uint8_t *buf, int n) {
    for (int i = 0; i < n; i++) {
        while (!neorv32_trng_data_avail());
        buf[i] = neorv32_trng_data_get();
    }
}
#endif

/* ── Benchmark / Timing ───────────────────────────────────────── */

#ifdef LOCAL_BUILD
#include <time.h>
static clock_t bench_start;

void bench_reset(void) {
    bench_start = clock();
}

uint32_t bench_cycles(void) {
    /* Local mode: return elapsed microseconds (approximation) */
    clock_t now = clock();
    return (uint32_t)((now - bench_start) * 1000000 / CLOCKS_PER_SEC);
}
#else
static uint64_t bench_start;

void bench_reset(void) {
    bench_start = neorv32_cpu_get_cycle();
}

uint32_t bench_cycles(void) {
    return (uint32_t)(neorv32_cpu_get_cycle() - bench_start);
}
#endif

/* ── info command ─────────────────────────────────────────────── */

static void show_info(void) {
    io_puts("DE2Extra Crypto Terminal\n");
    io_puts("========================\n");
    io_puts("Target: NEORV32 RISC-V @ 50 MHz\n");
    io_puts("ISA:    RV32IMC + Zfinx + Zbkb + Zbkc + Zbkx\n");
    io_puts("        Zkne + Zknd + Zknh (AES/SHA)\n");
    io_puts("        Zksed + Zksh (SM4/SM3)\n");
    io_puts("Memory: IMEM 32KB, DMEM 16KB\n");
    io_puts("Build:  " __DATE__ " " __TIME__ "\n");
#ifdef LOCAL_BUILD
    io_puts("Mode:   LOCAL (native GCC)\n");
#else
    io_puts("Mode:   NEORV32 (bare-metal)\n");
#endif
    io_puts("\n");
}

/* ── help command ─────────────────────────────────────────────── */

static void show_help(void) {
    io_puts(
        "Commands:\n"
        "  help                              Show this help\n"
        "  clear                             Clear screen\n"
        "  info                              Show system information\n"
        "  aes enc <key> <pt>                AES-128 ECB encrypt (hex)\n"
        "  aes dec <key> <ct>                AES-128 ECB decrypt (hex)\n"
        "  sha256 <msg>                      SHA-256 hash (hex input)\n"
        "  sha512 <msg>                      SHA-512 hash (hex input)\n"
        "  sm4 enc <key> <pt>                SM4 encrypt (hex)\n"
        "  sm3 <msg>                         SM3 hash (hex input)\n"
        "  trng [n]                          Read n random bytes (default 16)\n"
        "  bench                             Run all benchmarks\n"
        "  hex <addr> [n]                    Memory dump (not implemented)\n"
        "  led <val>                         Set LED output (not implemented)\n"
        "\n"
    );
}

/* ── Command handlers ─────────────────────────────────────────── */

static int cmd_aes(int argc, char *args[]) {
    if (argc < 3) goto usage;

    uint8_t key[16], data[16], out[16];
    int is_enc;

    if (strcmp(args[1], "enc") == 0)      is_enc = 1;
    else if (strcmp(args[1], "dec") == 0) is_enc = 0;
    else goto usage;

    if (hex_decode(args[2], key, 16) != 16) {
        io_puts("FFF0 > ERR: key must be 16 bytes (32 hex chars)\n");
        return 0xFFF0;
    }
    if (argc < 4 || hex_decode(args[3], data, 16) != 16) {
        io_puts("FFF0 > ERR: data must be 16 bytes (32 hex chars)\n");
        return 0xFFF0;
    }

    uint32_t rk[44];
    aes128_key_expand(key, rk);

    if (is_enc) aes128_enc_block(data, rk, out);
    else        aes128_dec_block(data, rk, out);

    print_digest("", out, 16);
    return 0;

usage:
    io_puts("FFFF > Usage: aes enc <key> <pt> | aes dec <key> <ct>\n");
    return 0xFFFF;
}

static int cmd_sha256(int argc, char *args[]) {
    if (argc < 2) {
        io_puts("FFFF > Usage: sha256 <hex-msg>\n");
        return 0xFFFF;
    }
    uint8_t msg[1024], digest[32];
    int len = hex_decode(args[1], msg, sizeof(msg));
    if (len < 0) {
        io_puts("FFF0 > ERR: invalid hex input\n");
        return 0xFFF0;
    }
    sha256_hash(msg, len, digest);
    print_digest("", digest, 32);
    return 0;
}

static int cmd_sha512(int argc, char *args[]) {
    if (argc < 2) {
        io_puts("FFFF > Usage: sha512 <hex-msg>\n");
        return 0xFFFF;
    }
    uint8_t msg[1024], digest[64];
    int len = hex_decode(args[1], msg, sizeof(msg));
    if (len < 0) {
        io_puts("FFF0 > ERR: invalid hex input\n");
        return 0xFFF0;
    }
    sha512_hash(msg, len, digest);
    print_digest("", digest, 64);
    return 0;
}

static int cmd_sm4(int argc, char *args[]) {
    if (argc < 4) goto usage;
    if (strcmp(args[1], "enc") != 0) goto usage;

    uint8_t key[16], data[16], out[16];
    if (hex_decode(args[2], key, 16) != 16) {
        io_puts("FFF0 > ERR: key must be 16 bytes (32 hex chars)\n");
        return 0xFFF0;
    }
    if (hex_decode(args[3], data, 16) != 16) {
        io_puts("FFF0 > ERR: data must be 16 bytes (32 hex chars)\n");
        return 0xFFF0;
    }
    uint32_t rk[32];
    sm4_key_schedule(key, rk);
    sm4_encrypt(data, rk, out);
    print_digest("", out, 16);
    return 0;

usage:
    io_puts("FFFF > Usage: sm4 enc <key> <pt>\n");
    return 0xFFFF;
}

static int cmd_sm3(int argc, char *args[]) {
    if (argc < 2) {
        io_puts("FFFF > Usage: sm3 <hex-msg>\n");
        return 0xFFFF;
    }
    uint8_t msg[1024], digest[32];
    int len = hex_decode(args[1], msg, sizeof(msg));
    if (len < 0) {
        io_puts("FFF0 > ERR: invalid hex input\n");
        return 0xFFF0;
    }
    sm3_hash(msg, len, digest);
    print_digest("", digest, 32);
    return 0;
}

static int cmd_trng(int argc, char *args[]) {
    int n = 16;
    if (argc >= 2) {
        n = 0;
        for (char *p = args[1]; *p; p++) {
            if (*p < '0' || *p > '9') { n = -1; break; }
            n = n * 10 + (*p - '0');
        }
        if (n <= 0 || n > 1024) {
            io_puts("FFF0 > ERR: n must be 1..1024\n");
            return 0xFFF0;
        }
    }
    uint8_t buf[1024];
    trng_bytes(buf, n);
    put_hex_buf(buf, n);
    io_puts("\n");
    return 0;
}

static int cmd_bench(void) {
    io_puts("Benchmark (lower is better):\n");
    io_puts("=============================\n");

    uint8_t key[16], pt[16], ct[16], msg[64], digest[64];
    uint32_t rk_aes[44], rk_sm4[32];
    int i;

    /* prepare test data */
    for (i = 0; i < 16; i++) { key[i] = (uint8_t)i; pt[i] = (uint8_t)(0x10 + i); }
    for (i = 0; i < 64; i++) msg[i] = (uint8_t)i;

#ifdef LOCAL_BUILD
#define BENCH_ITERS 10000
#else
#define BENCH_ITERS 1000
#endif

    bench_reset();
    aes128_key_expand(key, rk_aes);
    for (i = 0; i < BENCH_ITERS; i++) aes128_enc_block(pt, rk_aes, ct);
    uint32_t t_aes = bench_cycles();
    io_puts("AES-128 enc  x"); put_hex32(BENCH_ITERS); io_puts(": "); put_hex32(t_aes);
#ifdef LOCAL_BUILD
    io_puts(" us\n");
#else
    io_puts(" cycles\n");
#endif

    bench_reset();
    for (i = 0; i < BENCH_ITERS; i++) sha256_hash(msg, 64, digest);
    uint32_t t_sha256 = bench_cycles();
    io_puts("SHA-256      x"); put_hex32(BENCH_ITERS); io_puts(": "); put_hex32(t_sha256);
#ifdef LOCAL_BUILD
    io_puts(" us\n");
#else
    io_puts(" cycles\n");
#endif

    bench_reset();
    for (i = 0; i < BENCH_ITERS; i++) sha512_hash(msg, 64, digest);
    uint32_t t_sha512 = bench_cycles();
    io_puts("SHA-512      x"); put_hex32(BENCH_ITERS); io_puts(": "); put_hex32(t_sha512);
#ifdef LOCAL_BUILD
    io_puts(" us\n");
#else
    io_puts(" cycles\n");
#endif

    bench_reset();
    sm4_key_schedule(key, rk_sm4);
    for (i = 0; i < BENCH_ITERS; i++) sm4_encrypt(pt, rk_sm4, ct);
    uint32_t t_sm4 = bench_cycles();
    io_puts("SM4    enc   x"); put_hex32(BENCH_ITERS); io_puts(": "); put_hex32(t_sm4);
#ifdef LOCAL_BUILD
    io_puts(" us\n");
#else
    io_puts(" cycles\n");
#endif

    bench_reset();
    for (i = 0; i < BENCH_ITERS; i++) sm3_hash(msg, 64, digest);
    uint32_t t_sm3 = bench_cycles();
    io_puts("SM3          x"); put_hex32(BENCH_ITERS); io_puts(": "); put_hex32(t_sm3);
#ifdef LOCAL_BUILD
    io_puts(" us\n");
#else
    io_puts(" cycles\n");
#endif

#undef BENCH_ITERS
    return 0;
}

/* ── Command dispatch ─────────────────────────────────────────── */

static int dispatch(int argc, char *args[]) {
    if (argc == 0) return 0;

    char *cmd = args[0];

    if (strcmp(cmd, "help") == 0 || strcmp(cmd, "?") == 0) {
        show_help();
        return 0;
    }
    if (strcmp(cmd, "clear") == 0 || strcmp(cmd, "cls") == 0) {
        io_puts("\033[2J\033[H");  /* ANSI clear screen + home cursor */
        return 0;
    }
    if (strcmp(cmd, "info") == 0) {
        show_info();
        return 0;
    }
    if (strcmp(cmd, "aes") == 0) {
        return cmd_aes(argc, args);
    }
    if (strcmp(cmd, "sha256") == 0) {
        return cmd_sha256(argc, args);
    }
    if (strcmp(cmd, "sha512") == 0) {
        return cmd_sha512(argc, args);
    }
    if (strcmp(cmd, "sm4") == 0) {
        return cmd_sm4(argc, args);
    }
    if (strcmp(cmd, "sm3") == 0) {
        return cmd_sm3(argc, args);
    }
    if (strcmp(cmd, "trng") == 0) {
        return cmd_trng(argc, args);
    }
    if (strcmp(cmd, "bench") == 0) {
        return cmd_bench();
    }
    if (strcmp(cmd, "hex") == 0 || strcmp(cmd, "led") == 0) {
        io_puts("FFF0 > Not implemented in this build\n");
        return 0xFFF0;
    }

    io_puts("FFFF > ERR: unknown command. Type 'help' for command list.\n");
    return 0xFFFF;
}

/* ── Entry point ──────────────────────────────────────────────── */

#ifndef LOCAL_BUILD
/* NEORV32 bare-metal entry */
int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD_RATE, 0);
    neorv32_gpio_dir_set(0xFFFFFFFFu);
    board_set_status(LCD_STATUS_CRYPTO);
    trng_init();

    io_puts("\nDE2Extra Crypto Terminal v0.1\n");
    io_puts("Type 'help' for commands.\n\n");

    while (1) {
        io_puts("0000 > ");
        if (!read_line()) continue;

        char *args[MAX_ARGS];
        int argc = parse_args(args, MAX_ARGS);
        cmd_last = dispatch(argc, args);
    }
    return 0;
}
#else
/* LOCAL_BUILD: native test with stdin/stdout */
int main(void) {
    trng_init();
    show_info();

    while (1) {
        io_puts("0000 > ");
        if (read_line() == 0) {
            /* EOF — exit */
            io_puts("\n");
            break;
        }

        char *args[MAX_ARGS];
        int argc = parse_args(args, MAX_ARGS);
        cmd_last = dispatch(argc, args);

        /* Echo return code */
        io_puts("(");
        put_hex32((uint32_t)cmd_last);
        io_puts(") ");
    }
    return 0;
}
#endif
