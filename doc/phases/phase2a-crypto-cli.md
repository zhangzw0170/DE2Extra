# Phase 2a: 密码学终端 — C 软件

> 总纲: `../implementation_plan.md` | 并行: Phase 2b (`phase2b-vga-terminal.md`)
> 工作目录: `sw/app/crypto_cli/`

## 本阶段概述

纯 C 软件实现 AES-128、SHA-256/512、SM4、SM3 密码算法，带 UART 命令行界面。
NEORV32 已启用 Zk* RISC-V 标量密码学 ISA 扩展，CPU 硬件支持相关指令。

**两个版本都要保留**: 纯 C 参考实现 + Zk* 指令加速版本，`bench` 命令对比性能。

**当前结论 (2026-05-23):** Phase 2a 的“纯 C 基线版”已经完成并上板验证；本阶段剩余工作集中在 Zk* 指令加速版和性能对比。

---

## 验收表

> 状态: 2026-05-23
> ☑ = 完成, 🟡 = 待做, ❌ = 未开始

| # | 验收项 | 状态 | 说明 |
|---|---|---|---|
| 1 | AES-128 ECB 纯 C | ☑ | NIST FIPS-197 测试向量通过 |
| 2 | SHA-256 纯 C | ☑ | NIST FIPS-180-4 测试向量通过 |
| 3 | SHA-512 纯 C | ☑ | NIST FIPS-180-4 测试向量通过 |
| 4 | SM4 纯 C | ☑ | GB/T 32907-2016 测试向量通过 |
| 5 | SM3 纯 C | ☑ | GB/T 32905-2016 测试向量通过 |
| 6 | UART CLI | ☑ | 命令解析 + hex I/O + 错误处理 |
| 7 | Docker 交叉编译 | ☑ | 当前实机镜像 text=14,248B，仍在 32KB IMEM 内 |
| 8 | AES Zk* 加速 | ❌ | 用 aes32esmi/aes32dsi 替代查表 |
| 9 | SHA-256 Zk* 加速 | ❌ | 用 sha256sig0/1 + sha256sum0/1 替代移位 |
| 10 | SHA-512 Zk* 加速 | ❌ | 用 sha512sig0h/l + sha512sum0r/1r 替代 |
| 11 | SM4 Zk* 加速 | ❌ | 用 sm4ed/sm4ks 替代 S-box 查表 |
| 12 | SM3 Zk* 加速 | ❌ | 用 sm3p0/sm3p1 替代 P0/P1 函数 |
| 13 | `bench` 性能对比 | ❌ | 纯 C vs Zk* 加速 cycle 对比输出 |
| 14 | TRNG 真随机验证 | 🟡 | 真机已能读数，统计验证未做 |
| 15 | 基线上板验证 | ☑ | `crypto_cli` 已单独烧录；RS-232 命令交互和 LCD 状态已确认 |

---

## 命令列表

```
help                  — 显示帮助
info                  — 系统信息
cls                   — 清屏
aes enc <key> <pt>    — AES-128 加密 (key/pt 为 hex)
aes dec <key> <ct>    — AES-128 解密
sha256 <hex-msg>      — SHA-256 哈希
sha512 <hex-msg>      — SHA-512 哈希
sm4 <key> <pt>        — SM4 加密
sm3 <hex-msg>         — SM3 哈希
trng [n]              — 读 n 个 TRNG 随机数
bench                 — 性能基准 (纯C vs Zk* 加速)
```

## 已完成的实机验证

- 串口链路: RS-232 `COM10`, `115200 8N1`
- 启动画面: `DE2Extra Crypto Terminal v0.1`
- 命令验证:
  - `info`
  - `help`
  - `aes enc` / `aes dec`
  - `sha256`
  - `sha512`
  - `sm4 enc`
  - `sm3`
  - `trng 16`
  - `bench`
- LCD 状态:
  - 旧问题: 顶层仍挂 `lcd_status.vhd`，未写专用状态时会显示 `DE2Extra SDRAM / TESTING...`
  - 现状态: `crypto_cli` 启动后主动写 `0x2-------`，LCD 显示 `DE2Extra Crypto / UART CLI READY`

---

## Zk* 指令加速方案

### 架构: 双版本并存

```
crypto_aes.c  →  aes_encrypt()        [纯 C, 查表, 保留]
             →  aes_encrypt_zkn()     [Zk*, aes32esmi/aes32dsi, 新增]

crypto_sha.c  →  sha256_transform()   [纯 C, 移位, 保留]
             →  sha256_transform_zkn()[Zk*, sha256sig0/sum0, 新增]

crypto_sm.c   →  sm4_encrypt()        [纯 C, S-box, 保留]
             →  sm4_encrypt_zks()     [Zk*, sm4ed/sm4ks, 新增]
             →  sm3_compress()        [纯 C, P0/P1, 保留]
             →  sm3_compress_zks()    [Zk*, sm3p0/sm3p1, 新增]
```

- 纯 C 函数**保留不动**，Zk* 加速函数**新增在同文件**
- `bench` 命令跑两组: `bench_sw()` + `bench_hw()`，输出 cycle 对比
- LOCAL_BUILD 编译时 Zk* 函数不参与 (只有 NEORV32 target 有这些指令)

### NEORV32 支持的 Zk* 指令编码

从 `neorv32_cpu_trace.vhd` 提取:

| 指令 | opcode | funct3 | funct7/imm | 格式 |
|---|---|---|---|---|
| `aes32esi`   | 0110011 (0x33) | 000 | --10001-- | R, bs in rs2[31:30] |
| `aes32esmi`  | 0110011 (0x33) | 000 | --10011-- | R, bs in rs2[31:30] |
| `aes32dsi`   | 0110011 (0x33) | 000 | --10101-- | R, bs in rs2[31:30] |
| `aes32dsmi`  | 0110011 (0x33) | 000 | --10111-- | R, bs in rs2[31:30] |
| `sha256sig0` | 0010011 (0x13) | 001 | imm=0x102 | I-type |
| `sha256sig1` | 0010011 (0x13) | 001 | imm=0x103 | I-type |
| `sha256sum0` | 0010011 (0x13) | 001 | imm=0x100 | I-type |
| `sha256sum1` | 0010011 (0x13) | 001 | imm=0x101 | I-type |
| `sha512sig0h`| 0110011 (0x33) | 000 | --0101110-- | R-type |
| `sha512sig0l`| 0110011 (0x33) | 000 | --0101010-- | R-type |
| `sha512sig1h`| 0110011 (0x33) | 000 | --0101111-- | R-type |
| `sha512sig1l`| 0110011 (0x33) | 000 | --0101011-- | R-type |
| `sha512sum0r`| 0110011 (0x33) | 000 | --0101000-- | R-type |
| `sha512sum1r`| 0110011 (0x33) | 000 | --0101001-- | R-type |
| `sm3p0` | 0010011 (0x13) | 001 | imm=0x108 | I-type |
| `sm3p1` | 0010011 (0x13) | 001 | imm=0x109 | I-type |
| `sm4ed`  | 0110011 (0x33) | 000 | --11000-- | R, bs in rs2[31:30] |
| `sm4ks`  | 0110011 (0x33) | 000 | --11010-- | R, bs in rs2[31:30] |

### inline asm 方案

**方案 A (推荐): NEORV32 官方 intrinsic 库**

NEORV32 自带 `neorv32_intrinsics.h` (2026-04-06 重构)，提供 `.insn` 封装，不用手算编码：

```c
#include "neorv32_intrinsics.h"

// I-type (SHA-256 / SM3)
#define zk_sha256sig0(x) RISCV_INSTR_I_TYPE(0x13, 0x1, (x), 0x102)
#define zk_sha256sum0(x) RISCV_INSTR_I_TYPE(0x13, 0x1, (x), 0x100)
#define zk_sm3p0(x)      RISCV_INSTR_I_TYPE(0x13, 0x1, (x), 0x108)

// R-type (AES / SM4 / SHA-512)
#define zk_aes32esmi(rs1,rs2) RISCV_INSTR_R_TYPE(0x33, 0x0, 0x13, (rs1), (rs2))
#define zk_aes32dsi(rs1,rs2)  RISCV_INSTR_R_TYPE(0x33, 0x0, 0x15, (rs1), (rs2))
#define zk_sm4ed(rs1,rs2)     RISCV_INSTR_R_TYPE(0x33, 0x0, 0x18, (rs1), (rs2))
```

**方案 B (备选): 手写 `.insn` inline asm**

```c
static inline uint32_t zk_sha256sig0(uint32_t x) {
    uint32_t r;
    asm volatile (".insn i 0x13, 0x1, %0, %1, 0x102" : "=r"(r) : "r"(x));
    return r;
}
```
```

### `bench` 输出格式 (目标)

```
=== Crypto Benchmark (100 iterations) ===
              Software    Zk* HW     Speedup
AES-128 enc  00123456    00012345   10.0x
SHA-256      00098765    00009876   10.0x
SHA-512      00112233    00011223   10.0x
SM4          00055667    00005566   10.0x
SM3          00044332    00004433   10.0x
```

---

## 源码清单

| 文件 | 行数 | 说明 |
|---|---|---|
| `crypto.h` | ~130 | 类型定义 + API 声明 |
| `crypto_aes.c` | ~284 | AES-128 ECB (纯 C + 待加 Zk*) |
| `crypto_sha.c` | ~329 | SHA-256/512 (纯 C + 待加 Zk*) |
| `crypto_sm.c` | ~331 | SM4 + SM3 (纯 C + 待加 Zk*) |
| `main.c` | ~565 | CLI 框架 + 命令分派 + bench |

---

## 待完成

1. 在 `crypto_aes.c` 新增 `aes_encrypt_zkn()` / `aes_decrypt_zkn()`
2. 在 `crypto_sha.c` 新增 `sha256_transform_zkn()` / `sha512_block_zkn()`
3. 在 `crypto_sm.c` 新增 `sm4_encrypt_zks()` / `sm3_compress_zks()`
4. 更新 `bench` 命令输出纯 C vs Zk* 对比表
5. 在 de2shell 的 `crypto.c` 中合并完整功能 (当前是桩)
6. 真机验证 TRNG + Zk* 加速正确性

---

## 参考资源

### NEORV32 官方
- **intrinsic 库**: `neorv32/rtl/sw/lib/include/neorv32_intrinsics.h` — `RISCV_INSTR_R_TYPE()` / `RISCV_INSTR_I_TYPE()` 封装
- **commit f470fb3** (2026-04-06): 重构 intrinsic 为 `.insn` 伪指令，零开销编译

### RISC-V 标准参考
- **riscv-crypto 仓库**: https://github.com/riscv/riscv-crypto
  - `benchmarks/share/riscv-crypto-intrinsics.h` — 全部 Zk* 指令 inline asm 封装
  - `doc/scalar/riscv-crypto-scalar-zkne.adoc` — AES 指令规范
- **RISC-V Cryptography Spec (ratified v1.0)**: https://docs.riscv.org/reference/isa/extensions/crypto-scalar/_attachments/riscv-crypto-spec-scalar.pdf
- **指令编码表**: https://github.com/androidmiao/riscv-opcodes — RV32 Zkn/Zks 完整 opcode 定义

### 实现参考
- **Linux kernel RV32 AES-Zkn**: https://lists.infradead.org/pipermail/linux-riscv/2023-July/037153.html
  - `arch/riscv/crypto/aes-riscv32-zkned.S` — 完整 AES-128 RV32 汇编实现
  - `qround` 宏模式: 每轮 4 条 `aes32esmi`，手动处理 ShiftRows
  - 密钥扩展用 `aes32esi` 替代查表
  - RISC-V Summit 数据: **~4x 加速，代码量 0.3x**
- **Rust stdarch riscv32/zk.rs**: https://doc.rust-lang.org/src/core/stdarch/crates/core_arch/src/riscv32/zk.rs.html
  - 全部 Zk* intrinsic 的 Rust 封装，含详细语义注释
- **Sylvain Pelissier 博客**: https://sylvainpelissier.gitlab.io/posts/2023-01-22-risc-v-cryptography-extension/
  - GCC `-march=rv64idzkn` 编译方法 + QEMU 7.1+ 验证流程
- **Riscvonomicon**: https://riscvonomicon.github.io/book/extensions/zk/zkned/32bit.html
  - 最清晰的 AES-32 指令语义解释 + 完整轮函数/密钥扩展伪代码
