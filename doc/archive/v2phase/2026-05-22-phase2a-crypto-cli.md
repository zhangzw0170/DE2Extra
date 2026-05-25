# Phase 2a: Crypto CLI — Implementation Plan

> **计划执行时间: 2026-05-23 11:45** | **归档: 全部标准测试向量通过，Docker 交叉编译通过**
> **Status: COMPLETE (2026-05-23)** — 纯 C 实现完成，全部标准测试向量通过，Docker 交叉编译通过。
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pure C software crypto terminal via UART — AES/SHA/SM4/SM3 + TRNG verification + CLI command parser.

**Architecture:** Bare-metal C using NEORV32 runtime (`neorv32_rte_setup`). Crypto operations via inline assembly for Zk* ISA extensions. UART0 for I/O. No OS, no VGA dependency.

**Tech Stack:** riscv32-unknown-elf-gcc (Docker), NEORV32 sw framework, NIST/国密 test vectors

---

## File Structure

| File | Responsibility |
|---|---|
| `sw/app/crypto_cli/main.c` | **新建** — CLI 入口，命令解析，输出格式化 |
| `sw/app/crypto_cli/crypto.h` | **新建** — Crypto 函数声明 + 内联汇编原型 |
| `sw/app/crypto_cli/crypto_aes.c` | **新建** — AES-128 ECB 加密/解密 |
| `sw/app/crypto_cli/crypto_sha.c` | **新建** — SHA-256/SHA-512 |
| `sw/app/crypto_cli/crypto_sm.c` | **新建** — SM4/SM3 |
| `sw/app/crypto_cli/crypto_trng.c` | **新建** — TRNG 读取 + 随机性统计 |
| `sw/app/crypto_cli/crypto_bench.c` | **新建** — 性能基准测试 |
| `sw/app/crypto_cli/makefile` | **新建** — 复制 hello/makefile，添加新 .c 文件 |

---

## Task 1: 创建项目骨架和 makefile

**Files:**
- Create: `sw/app/crypto_cli/makefile`
- Create: `sw/app/crypto_cli/main.c`

- [ ] **Step 1: 创建 makefile**

复制 `sw/app/hello/makefile`，修改添加新的源文件：

```makefile
# DE2Extra — Crypto CLI Makefile
MARCH = rv32imc_zicsr_zicntr_zifencei_zfinx_zbkb_zbkc_zbkx_zknd_zkne_zknh_zksed_zksh
MABI  = ilp32
EFFORT = -Os
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k
NEORV32_HOME ?= ../../neorv32
include $(NEORV32_HOME)/sw/common/common.mk
```

- [ ] **Step 2: 创建最小 main.c — UART hello + 命令提示符**

```c
#include <neorv32.h>

#define BAUD_RATE 115200

static void puts(const char *s) {
    neorv32_uart0_puts(s);
}

int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD_RATE, 0);

    puts("\n0000 > ");
    while (1) {
        char c = neorv32_uart0_getc();
        if (c == '\r') {
            puts("\n0000 > ");
        } else {
            neorv32_uart0_putc(c);
        }
    }
    return 0;
}
```

- [ ] **Step 3: Docker 编译 + 烧录验证**

Run: `cd sw && ./build.sh app/crypto_cli`
Expected: 编译成功，UART 输出 "0000 > "，输入字符回显。

---

## Task 2: 实现命令解析器

**Files:**
- Modify: `sw/app/crypto_cli/main.c`

- [ ] **Step 1: 实现简单的命令行解析**

```c
#include <string.h>

#define CMD_BUF_SIZE 128
#define MAX_ARGS 8

static char cmd_buf[CMD_BUF_SIZE];
static int cmd_pos;

static void puts(const char *s);
static void put_hex32(uint32_t val);
static int readline(void);
static int parse_args(char *args[], int max_args);

int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD_RATE, 0);

    puts("\nDE2Extra Crypto Terminal\n");
    puts("Type 'help' for commands.\n");

    while (1) {
        puts("0000 > ");
        if (!readline()) continue;

        char *args[MAX_ARGS];
        int argc = parse_args(args, MAX_ARGS);
        if (argc == 0) continue;

        // command dispatch (Phase 2a 只实现 help + clear)
        if (strcmp(args[0], "help") == 0) {
            puts("Commands: help, clear, aes, sha256, sha512,");
            puts("         sm4, sm3, trng, bench, info, hex, led\n");
            cmd_last = 0;  // 成功
        } else if (strcmp(args[0], "clear") == 0) {
            puts("\033[2J\n");  // ANSI clear screen
            cmd_last = 0;
        } else {
            puts("ERR: unknown command\n");
            cmd_last = 0xFFFF;
        }
    }
}
```

`readline()` 读取字符到 `cmd_buf` 直到 `\r`，`parse_args()` 按空格分割。
`cmd_last` 变量追踪最后返回码（0=成功，0xFFFF=失败）。

- [ ] **Step 2: 编译验证命令解析**

Run: `./build.sh app/crypto_cli`
Expected: `help` 打印命令列表，`clear` 清屏，未知命令返回错误。

---

## Task 3: 实现 AES-128 ECB

**Files:**
- Create: `sw/app/crypto_cli/crypto.h`
- Create: `sw/app/crypto_cli/crypto_aes.c`

- [ ] **Step 1: 定义 AES 内联汇编接口**

NEORV32 Zkne/Zknd 使用 `.insn` directive 或直接用 NEORV32 提供的 intrinsics。查看 `neorv32/sw/lib/include/neorv32.h` 中的 crypto 相关定义。

```c
// crypto.h
#ifndef CRYPTO_H
#define CRYPTO_H

#include <stdint.h>

void aes128_enc(const uint32_t key[4], const uint32_t pt[4], uint32_t ct[4]);
void aes128_dec(const uint32_t key[4], const uint32_t ct[4], uint32_t pt[4]);

#endif
```

- [ ] **Step 2: 实现 aes128_enc**

AES-128 状态: 4 个 32-bit word (x0-x3)，10 轮 SubBytes→ShiftRows→MixColumns→AddRoundKey。
使用 NEORV32 的 `aes32esmi` / `aes32esi` 指令做 SubBytes+ShiftRows+MixColumns 一步完成。

关键：先用 NIST FIPS-197 Appendix B 测试向量验证。密钥 `2b7e151628aed2a6abf7158809cf4f3c`，明文 `6bc1bee22e409f96e93d7e117393172a`，密文 `3ad77bb40d7a3660a89ecaf32466ef97`。

- [ ] **Step 3: 编译 + 验证 NIST 测试向量**

Run: 在 main.c 中添加 `aes enc 2b7e151628aed2a6abf7158809cf4f3c 6bc1bee22e409f96e93d7e117393172a`
Expected: 输出密文 `3ad77bb40d7a3660a89ecaf32466ef97`

---

## Task 4: 实现 SHA-256

**Files:**
- Modify: `sw/app/crypto_cli/crypto.h`
- Create: `sw/app/crypto_cli/crypto_sha.c`

- [ ] **Step 1: 实现 sha256**

使用 NEORV32 `sha256sig0` / `sha256sig1` / `sha256sum0` / `sha256sum1` 指令。
NIST FIPS-180-4 示例: "abc" → `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.

- [ ] **Step 2: 编译 + 验证**

Expected: `sha256 616263` 输出 `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`

---

## Task 5: 实现 SHA-512 / SM4 / SM3

**Files:**
- Modify: `sw/app/crypto_cli/crypto.h`
- Modify: `sw/app/crypto_cli/crypto_sha.c`
- Modify: `sw/app/crypto_cli/crypto_sm.c`

- [ ] **Step 1: 添加 sha512 到 crypto_sha.c**

NIST FIPS-180-4 示例: "abc" → `ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f`

- [ ] **Step 2: 实现 SM4**

GB/T 32907-2016 测试向量。密钥 `0123456789abcdeffedcba9876543210`，明文 `0123456789abcdeffedcba9876543210`，密文 `681edf34d206965e86b3e94f536e4246`。

- [ ] **Step 3: 实现 SM3**

GB/T 32905-2016 测试向量。消息 "abc" → 32 字节摘要。

- [ ] **Step 4: 编译 + 全部测试向量验证**

Expected: 所有 NIST/国密测试向量通过。

---

## Task 6: 实现 TRNG 读取 + 性能基准

**Files:**
- Create: `sw/app/crypto_cli/crypto_trng.c`
- Create: `sw/app/crypto_cli/crypto_bench.c`
- Modify: `sw/app/crypto_cli/main.c`

- [ ] **Step 1: 实现 TRNG 读取**

NEORV32 TRNG 寄存器位于 `NEORV32_TRNG` 地址。使用 `neorv32_trng_get()` 读取随机字节。
`trng [n]` 命令输出 n 字节十六进制。

- [ ] **Step 2: 实现性能基准**

`bench` 命令依次运行 AES/SHA/SM4/SM3，使用 `read_csr(mcycle)` 计时，打印每个算法的 cycles 和时间 (@50MHz)。

- [ ] **Step 3: 实现 info 命令**

打印 CPU 信息、时钟频率、ISA 扩展列表、IMEM/DMEM 大小等 fastfetch 风格输出。

---

## Task 7: 集成 + 最终验证

**Files:**
- Modify: `sw/app/crypto_cli/main.c`

- [ ] **Step 1: 完善错误处理**

- 无效参数 → `FFFF > ERR: invalid arguments`
- hex 解析失败 → `FFFF > ERR: invalid hex`
- 所有已知命令正确分发

- [ ] **Step 2: 编译 + 检查 IMEM 大小**

Run: `./build.sh app/crypto_cli`
Expected: 编译成功。检查 `main.elf` 的 `.text` 段大小，确保 < 32KB (IMEM 限制)。
If overflow: 优化 `-Os`，移除冗余字符串，或考虑链接到 SDRAM 执行。

- [ ] **Step 3: 完整功能测试**

依次测试所有命令，与 NIST/国密测试向量对比。
Expected: 全部通过。

- [ ] **Step 4: 提交**

```bash
git add sw/app/crypto_cli/
git commit -m "feat: add crypto CLI with AES/SHA/SM4/SM3/TRNG"
```
