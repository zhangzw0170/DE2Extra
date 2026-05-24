/* monitor.c — RISC-V Assembly Monitor for de2shell
 *
 * Commands:
 *   regs              — show saved register snapshot
 *   dump ADDR [N]     — hex dump N words from memory
 *   peek ADDR         — read one word
 *   poke ADDR VAL     — write one word
 *   aes               — AES-128 instruction demo
 *   sha256            — SHA-256 instruction demo
 *   sm4               — SM4 instruction demo
 *   help              — show commands
 */

#include "vga_hal.h"
#include <stdint.h>

#ifdef LOCAL_BUILD
  #include <string.h>
#else
  #include "../crypto_cli/crypto_zk.h"
  static int strcmp(const char *a, const char *b) {
      while (*a && *a == *b) { a++; b++; }
      return (unsigned char)*a - (unsigned char)*b;
  }
  static int strncmp(const char *a, const char *b, int n) {
      while (n-- > 0 && *a && *a == *b) { a++; b++; }
      return (n < 0) ? 0 : (unsigned char)*a - (unsigned char)*b;
  }
#endif

/* ── Register Snapshot ────────────────────────────────────────── */

static uint32_t snap_x[32];
static const char *reg_names[32] = {
    "zero","ra","sp","gp","tp","t0","t1","t2",
    "s0","s1","a0","a1","a2","a3","a4","a5",
    "a6","a7","s2","s3","s4","s5","s6","s7",
    "s8","s9","s10","s11","t3","t4","t5","t6"
};

static void capture_regs_snapshot(void) {
    snap_x[0] = 0;
#ifdef LOCAL_BUILD
    for (int i = 1; i < 32; i++) {
        snap_x[i] = 0;
    }
#else
    __asm__ volatile ("mv %0, ra"  : "=r"(snap_x[1]));
    __asm__ volatile ("mv %0, sp"  : "=r"(snap_x[2]));
    __asm__ volatile ("mv %0, gp"  : "=r"(snap_x[3]));
    __asm__ volatile ("mv %0, tp"  : "=r"(snap_x[4]));
    __asm__ volatile ("mv %0, t0"  : "=r"(snap_x[5]));
    __asm__ volatile ("mv %0, t1"  : "=r"(snap_x[6]));
    __asm__ volatile ("mv %0, t2"  : "=r"(snap_x[7]));
    __asm__ volatile ("mv %0, s0"  : "=r"(snap_x[8]));
    __asm__ volatile ("mv %0, s1"  : "=r"(snap_x[9]));
    __asm__ volatile ("mv %0, a0"  : "=r"(snap_x[10]));
    __asm__ volatile ("mv %0, a1"  : "=r"(snap_x[11]));
    __asm__ volatile ("mv %0, a2"  : "=r"(snap_x[12]));
    __asm__ volatile ("mv %0, a3"  : "=r"(snap_x[13]));
    __asm__ volatile ("mv %0, a4"  : "=r"(snap_x[14]));
    __asm__ volatile ("mv %0, a5"  : "=r"(snap_x[15]));
    __asm__ volatile ("mv %0, a6"  : "=r"(snap_x[16]));
    __asm__ volatile ("mv %0, a7"  : "=r"(snap_x[17]));
    __asm__ volatile ("mv %0, s2"  : "=r"(snap_x[18]));
    __asm__ volatile ("mv %0, s3"  : "=r"(snap_x[19]));
    __asm__ volatile ("mv %0, s4"  : "=r"(snap_x[20]));
    __asm__ volatile ("mv %0, s5"  : "=r"(snap_x[21]));
    __asm__ volatile ("mv %0, s6"  : "=r"(snap_x[22]));
    __asm__ volatile ("mv %0, s7"  : "=r"(snap_x[23]));
    __asm__ volatile ("mv %0, s8"  : "=r"(snap_x[24]));
    __asm__ volatile ("mv %0, s9"  : "=r"(snap_x[25]));
    __asm__ volatile ("mv %0, s10" : "=r"(snap_x[26]));
    __asm__ volatile ("mv %0, s11" : "=r"(snap_x[27]));
    __asm__ volatile ("mv %0, t3"  : "=r"(snap_x[28]));
    __asm__ volatile ("mv %0, t4"  : "=r"(snap_x[29]));
    __asm__ volatile ("mv %0, t5"  : "=r"(snap_x[30]));
    __asm__ volatile ("mv %0, t6"  : "=r"(snap_x[31]));
#endif
}

/* ── Crypto Demo Helpers ───────────────────────────────────────── */

static void demo_aes(void) {
    uint32_t rs1 = 0xAABBCCDD, rs2 = 0x11223344;
    uint32_t r_esmi, r_esi;
#ifdef LOCAL_BUILD
    r_esmi = rs1 ^ rs2;
    r_esi  = r_esmi + 1;
#else
    r_esmi = zk_aes32esmi(rs1, rs2, 0);
    r_esi  = zk_aes32esi(rs1, rs2, 0);
#endif

    vga_puts("\n=== AES-128 Demo ===\n", VGA_CYAN);
    vga_puts("Input state:  0x", VGA_WHITE); vga_puthex32(rs1);
    vga_puts("\nRound key:    0x", VGA_WHITE); vga_puthex32(rs2);
    vga_puts("\n\naes32esmi (SubBytes+ShiftRows+MixColumns):\n", VGA_GREEN);
    vga_puts("  Encoding: 0x26B50533\n", VGA_GRAY);
    vga_puts("  Result:   0x", VGA_YELLOW); vga_puthex32(r_esmi);
    vga_puts("\n\naes32esi (SubBytes+ShiftRows, last round):\n", VGA_GREEN);
    vga_puts("  Encoding: 0x22B50533\n", VGA_GRAY);
    vga_puts("  Result:   0x", VGA_YELLOW); vga_puthex32(r_esi);
    vga_puts("\n", VGA_BLACK);
}

static void demo_sha256(void) {
    uint32_t rs1 = 0x12345678;
    uint32_t r_sig0, r_sum0;
#ifdef LOCAL_BUILD
    r_sig0 = (rs1 >> 7 | rs1 << 25) ^ (rs1 >> 18 | rs1 << 14) ^ (rs1 >> 3);
    r_sum0 = (rs1 >> 2 | rs1 << 30) ^ (rs1 >> 13 | rs1 << 19) ^ (rs1 >> 22 | rs1 << 10);
#else
    register uint32_t a0 asm("a0") = rs1;
    __asm__ volatile (".word 0x10251513" : "+r"(a0));
    r_sig0 = a0;
    a0 = rs1;
    __asm__ volatile (".word 0x10051513" : "+r"(a0));
    r_sum0 = a0;
#endif

    vga_puts("\n=== SHA-256 Demo ===\n", VGA_CYAN);
    vga_puts("Input word:   0x", VGA_WHITE); vga_puthex32(rs1);
    vga_puts("\n\nsha256sig0 (sigma0 function):\n", VGA_GREEN);
    vga_puts("  Encoding: 0x10251513\n", VGA_GRAY);
    vga_puts("  Result:   0x", VGA_YELLOW); vga_puthex32(r_sig0);
    vga_puts("\n\nsha256sum0 (Sigma0 function):\n", VGA_GREEN);
    vga_puts("  Encoding: 0x10051513\n", VGA_GRAY);
    vga_puts("  Result:   0x", VGA_YELLOW); vga_puthex32(r_sum0);
    vga_puts("\n", VGA_BLACK);
}

static void demo_sm4(void) {
    uint32_t rs1 = 0xAABBCCDD, rs2 = 0x11223344;
    uint32_t r_sm4ed, r_sm4ks;
#ifdef LOCAL_BUILD
    r_sm4ed = rs1 ^ rs2;
    r_sm4ks = rs1 + rs2;
#else
    register uint32_t a0 asm("a0") = rs1;
    register uint32_t a1 asm("a1") = rs2;
    __asm__ volatile (".word 0x30B50533" : "+r"(a0) : "r"(a1));
    r_sm4ed = a0;
    a0 = rs1; a1 = rs2;
    __asm__ volatile (".word 0x34B50533" : "+r"(a0) : "r"(a1));
    r_sm4ks = a0;
#endif

    vga_puts("\n=== SM4 Demo ===\n", VGA_CYAN);
    vga_puts("Input state:  0x", VGA_WHITE); vga_puthex32(rs1);
    vga_puts("\nRound key:    0x", VGA_WHITE); vga_puthex32(rs2);
    vga_puts("\n\nsm4ed (encrypt/decrypt round):\n", VGA_GREEN);
    vga_puts("  Encoding: 0x30B50533\n", VGA_GRAY);
    vga_puts("  Result:   0x", VGA_YELLOW); vga_puthex32(r_sm4ed);
    vga_puts("\n\nsm4ks (key schedule round):\n", VGA_GREEN);
    vga_puts("  Encoding: 0x34B50533\n", VGA_GRAY);
    vga_puts("  Result:   0x", VGA_YELLOW); vga_puthex32(r_sm4ks);
    vga_puts("\n", VGA_BLACK);
}

/* ── Hex Helpers ───────────────────────────────────────────────── */

static int hex4(char c) {
    if (c>='0'&&c<='9') return c-'0';
    if (c>='a'&&c<='f') return c-'a'+10;
    if (c>='A'&&c<='F') return c-'A'+10;
    return -1;
}

static uint32_t parse_hex(const char *s) {
    uint32_t v = 0;
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;
    while (*s) {
        int d = hex4(*s++);
        if (d < 0) break;
        v = (v << 4) | d;
    }
    return v;
}

/* ── Memory Operations ─────────────────────────────────────────── */

static void cmd_dump(uint32_t addr, int n) {
    volatile uint32_t *p = (volatile uint32_t*)(uintptr_t)addr;
    for (int i = 0; i < n; i++) {
        vga_puthex32(addr + i*4); vga_puts(": 0x", VGA_WHITE);
        vga_puthex32(p[i]);
        vga_puts("\n", VGA_BLACK);
    }
}

static void cmd_peek(uint32_t addr) {
    volatile uint32_t *p = (volatile uint32_t*)(uintptr_t)addr;
    vga_puts("0x", VGA_WHITE); vga_puthex32(addr);
    vga_puts(" = 0x", VGA_WHITE); vga_puthex32(*p);
    vga_puts("\n", VGA_BLACK);
}

static void cmd_poke(uint32_t addr, uint32_t val) {
    volatile uint32_t *p = (volatile uint32_t*)(uintptr_t)addr;
    *p = val;
    vga_puts("OK\n", VGA_GREEN);
}

static void cmd_regs(void) {
    capture_regs_snapshot();
    vga_puts("Registers (snapshot):\n", VGA_CYAN);
    for (int i = 0; i < 32; i += 4) {
        for (int j = 0; j < 4 && i+j < 32; j++) {
            vga_puts(reg_names[i+j], VGA_GREEN);
            vga_puts("=0x", VGA_GRAY);
            vga_puthex32(snap_x[i+j]);
            vga_puts("  ", VGA_BLACK);
        }
        vga_puts("\n", VGA_BLACK);
    }
}

/* ── Monitor Shell ─────────────────────────────────────────────── */

static int active = 0;
static char line[64];
static int  pos = 0;
static char saved_line[64];
static char history[8][64];
static int history_count = 0;
static int history_nav = -1;
static int esc_state = 0;

static void prompt(void) {
    vga_puts("riscvasm > ", VGA_GREEN);
}

static void redraw_input_line(int old_len) {
    vga_putc('\r', VGA_WHITE);
    prompt();
    for (int i = 0; i < pos; i++) {
        vga_putc(line[i], VGA_WHITE);
    }
    for (int i = pos; i < old_len; i++) {
        vga_putc(' ', VGA_WHITE);
    }
    vga_putc('\r', VGA_WHITE);
    prompt();
    for (int i = 0; i < pos; i++) {
        vga_putc(line[i], VGA_WHITE);
    }
}

static void history_store_current(void) {
    for (int i = 0; i <= pos; i++) {
        saved_line[i] = line[i];
    }
}

static void history_load(const char *src) {
    int i = 0;
    while (src[i] && i < (int)sizeof(line) - 1) {
        line[i] = src[i];
        i++;
    }
    line[i] = '\0';
    pos = i;
}

static void history_push(void) {
    if (pos == 0) {
        return;
    }
    if ((history_count > 0) && (strcmp(history[history_count - 1], line) == 0)) {
        return;
    }
    if (history_count < (int)(sizeof(history) / sizeof(history[0]))) {
        for (int i = 0; i <= pos; i++) {
            history[history_count][i] = line[i];
        }
        history_count++;
    } else {
        for (int i = 1; i < (int)(sizeof(history) / sizeof(history[0])); i++) {
            for (int j = 0; j < (int)sizeof(line); j++) {
                history[i - 1][j] = history[i][j];
            }
        }
        for (int i = 0; i <= pos; i++) {
            history[(sizeof(history) / sizeof(history[0])) - 1][i] = line[i];
        }
    }
}

static void history_prev(void) {
    int old_len = pos;
    if (history_count <= 0) {
        return;
    }
    if (history_nav < 0) {
        history_store_current();
        history_nav = history_count - 1;
    } else if (history_nav > 0) {
        history_nav--;
    } else {
        return;
    }
    history_load(history[history_nav]);
    redraw_input_line(old_len);
}

static void history_next(void) {
    int old_len = pos;
    if (history_nav < 0) {
        return;
    }
    if (history_nav < (history_count - 1)) {
        history_nav++;
        history_load(history[history_nav]);
    } else {
        history_nav = -1;
        history_load(saved_line);
    }
    redraw_input_line(old_len);
}

static void init(void) {
    vga_clear();
    vga_puts("RISC-V Assembly Monitor v0.2\n", VGA_CYAN);
    vga_puts("Commands: help regs peek poke dump aes sha256 sm4 q\n", VGA_GRAY);
    vga_puts("ISA: RV32IMC + Zicsr + Zicntr + Zifencei\n", VGA_GRAY);
    vga_puts("     Zbkb + Zbkc + Zbkx + Zkne + Zknd + Zknh + Zksed + Zksh\n\n", VGA_GRAY);
    prompt();
    active = 1;
    pos = 0;
    line[0] = '\0';
    saved_line[0] = '\0';
    history_nav = -1;
    esc_state = 0;
}

static void show_help(void) {
    vga_puts("Commands:\n", VGA_CYAN);
    vga_puts("  regs              Show register snapshot\n", VGA_WHITE);
    vga_puts("  dump ADDR [N]     Hex dump (default 8 words)\n", VGA_WHITE);
    vga_puts("  peek ADDR         Read one word\n", VGA_WHITE);
    vga_puts("  poke ADDR VAL     Write one word\n", VGA_WHITE);
    vga_puts("  aes               AES-128 instruction demo\n", VGA_YELLOW);
    vga_puts("  sha256            SHA-256 instruction demo\n", VGA_YELLOW);
    vga_puts("  sm4               SM4 instruction demo\n", VGA_YELLOW);
    vga_puts("  help              Show this help\n", VGA_WHITE);
    vga_puts("  q                 Return to shell\n", VGA_WHITE);
}

static void usage_peek(void) {
    vga_puts("Usage: peek ADDR\n", VGA_RED);
}

static void usage_poke(void) {
    vga_puts("Usage: poke ADDR VAL\n", VGA_RED);
}

static void usage_dump(void) {
    vga_puts("Usage: dump ADDR [N]\n", VGA_RED);
}

static void input(char c) {
    if (!active) return;
    if (c == 'q' || c == 'Q') { active = 0; return; }

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

    if (c == '\r' || c == '\n') {
        line[pos] = '\0';
        vga_puts("\n", VGA_BLACK);
        char *cmd = line;
        while (*cmd == ' ') cmd++;
        if (pos > 0) {
            history_push();
        }
        history_nav = -1;
        saved_line[0] = '\0';

        if (pos == 0) {
            /* empty */
        } else if (strcmp(cmd, "help") == 0) {
            show_help();
        } else if (strcmp(cmd, "regs") == 0) {
            cmd_regs();
        } else if (strcmp(cmd, "aes") == 0) {
            demo_aes();
        } else if (strcmp(cmd, "sha256") == 0 || strcmp(cmd, "sha") == 0) {
            demo_sha256();
        } else if (strcmp(cmd, "sm4") == 0) {
            demo_sm4();
        } else if (strcmp(cmd, "peek") == 0) {
            usage_peek();
        } else if (strcmp(cmd, "poke") == 0) {
            usage_poke();
        } else if (strcmp(cmd, "dump") == 0) {
            usage_dump();
        } else if (strncmp(cmd, "peek ", 5) == 0) {
            cmd_peek(parse_hex(cmd + 5));
        } else if (strncmp(cmd, "poke ", 5) == 0) {
            char *a = cmd + 5;
            while (*a == ' ') a++;
            uint32_t addr = parse_hex(a);
            while (*a && *a != ' ') a++;
            while (*a == ' ') a++;
            cmd_poke(addr, parse_hex(a));
        } else if (strncmp(cmd, "dump ", 5) == 0) {
            char *a = cmd + 5;
            while (*a == ' ') a++;
            uint32_t addr = parse_hex(a);
            while (*a && *a != ' ') a++;
            while (*a == ' ') a++;
            int n = (*a) ? (int)parse_hex(a) : 8;
            if (n <= 0) {
                n = 8;
            }
            if (n > 64) {
                n = 64;
            }
            cmd_dump(addr, n);
        } else {
            vga_puts("? Unknown. Type 'help'\n", VGA_RED);
        }
        pos = 0;
        line[0] = '\0';
        prompt();
    } else if (c == '\b' || c == 0x7F) {
        if (pos > 0) {
            pos--;
            line[pos] = '\0';
            vga_putc('\b', VGA_WHITE);
        }
    } else if (c >= ' ' && c < 0x7F && pos < (int)sizeof(line)-1) {
        line[pos++] = c;
        line[pos] = '\0';
        vga_putc(c, VGA_WHITE);
    }
}

static void update(void) {}
static int finish(void) { return !active; }

const program_t prog_monitor = {
    "RiscvAsm", "RISC-V monitor — regs/dump/peek/poke/aes/sha/sm4",
    init, update, input, NULL, finish
};
