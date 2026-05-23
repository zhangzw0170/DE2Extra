# Phase 2a: 密码学终端 — C 软件

> 总纲: `../implementation_plan.md` | 并行: Phase 2b (`phase2b-vga-terminal.md`)
> 工作目录: `sw/app/crypto_cli/`

## 本阶段概述

纯 C 软件，通过 UART 交互，不需要额外 VHDL。NEORV32 Crypto ISA 已全部启用。
可立即开始: 现有 UART+IMEM 环境即可开发测试，不依赖 Phase 1。

---

## 验收表

> 状态: 2026-05-23 — 纯 C 实现完成，本地 GCC + Docker 交叉编译均通过。
> ☑ = 已验收（本地 GCC + 标准测试向量），⬜ = 待上板验证。

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| 1 | AES-128 ECB 加密 | NIST FIPS-197 Appendix B 测试向量通过 | ☑ |
| 2 | AES-128 ECB 解密 | NIST FIPS-197 Appendix B 逆向测试向量通过 | ☑ |
| 3 | SHA-256 | NIST FIPS-180-4 示例 (空串/abc/448bit) 通过 | ☑ |
| 4 | SHA-512 | NIST FIPS-180-4 示例 (空串/abc) 通过 | ☑ |
| 5 | SM4 加密 | GB/T 32907-2016 测试向量 + 1M-ECB 通过 | ☑ |
| 6 | SM3 哈希 | GB/T 32905-2016 测试向量 (空串/abc/64B) 通过 | ☑ |
| 7 | TRNG 随机性 | 频率分布 0.8-1.2 均匀，无全零输出 | ⬜ (需要硬件 TRNG) |
| 8 | 性能统计 | 各算法打印 cycles 数，与理论值量级一致 | ⬜ (需要 CSR_CYCLE) |
| 9 | UART CLI | 命令解析正确，错误输入返回 `FFFF` | ☑ (本地 stdin/stdout) |
| 10 | 编译上板 | riscv-gcc 编译通过，.mif 生成，烧录运行 | 🟡 (Docker 交叉编译通过，待烧录) |

---

## 功能

1. **AES-128** (Zkne/Zknd): ECB 模式，NIST 测试向量验证
2. **SHA-256/SHA-512** (Zknh): 任意长度消息
3. **SM4** (Zksed): 国密对称加密
4. **SM3** (Zksh): 国密哈希
5. **TRNG**: 读取随机数，统计频率分布验证随机性
6. **性能统计**: Zicntr cycle counter 测量周期数
7. **UART CLI**: 命令解析，hex 输入统一格式

## 命令设计

```
  命令                参数                              说明
  ─────────────────────────────────────────────────────────────────
  help                                                 打印命令列表
  clear                                                清屏
  aes enc <key> <pt>    key/pt = hex string           AES-128 ECB 加密
  aes dec <key> <ct>    key 16 bytes, ct 16 bytes     AES-128 ECB 解密
  sha256 <msg>          msg = hex string              SHA-256 哈希
  sha512 <msg>          msg = hex string              SHA-512 哈希
  sm4 enc <key> <pt>    key/pt = hex, 16 bytes each   SM4 加密
  sm3 <msg>             msg = hex string              SM3 哈希
  trng [n]              n = bytes, default 16        读取 TRNG 随机数
  bench                                                运行全部性能基准测试
  info                                                 打印 fastfetch 系统信息
  hex <addr> [n]        addr = 32-bit hex             内存查看
  led <val>             val = 32-bit hex              控制 LED 输出
  clip                                                 输出剪贴板到 UART (Phase 3)
  screen                                               输出全屏到 UART (Phase 3)
```

- 参数格式统一 hex string，空格分隔
- 错误时返回码置 `FFFF`

## 编译与烧录流程

```bash
# 1. 编译 (Docker 内)
riscv32-unknown-elf-gcc -O2 \
  -march=rv32imczkne_zknd_zknh_zksed_zksh_zbkb_zbkc_zbkx_zfinx \
  -T link.ld -o app.elf main.c crypto.c

# 2. 生成 .mif (IMEM 初始化)
riscv32-unknown-elf-objcopy -O binary app.elf app.bin
bin2mif app.bin > imem_init.mif

# 3. Quartus 编译 → 烧录 .sof
# 或用 NEORV32 bootloader 从 UART 引导 (BOOT_MODE=0)
```

## AI 分工

2a 全部工作在 `sw/app/crypto_cli/` 目录下，与 2b 的 VHDL 工作零文件冲突。
2b 的双输出架构 (`terminal_putc`) 和命令设计是合并时的接口约定，本阶段先按 UART-only 实现。

---

## 实现记录 (2026-05-23)

### 源文件

| 文件 | 行数 | 说明 |
|---|---|---|
| `crypto.h` | 126 | 类型定义、函数声明，双模式 (LOCAL_BUILD / NEORV32) |
| `crypto_aes.c` | 283 | AES-128 ECB，含 Zkne/Zknd 内联汇编注释 |
| `crypto_sha.c` | 328 | SHA-256/512，含 Zknh 内联汇编注释 |
| `crypto_sm.c` | 331 | SM4 + SM3，含 Zksed/Zksh 内联汇编注释 |
| `main.c` | 522 | CLI 命令解析 + TRNG 驱动 + bench + info |
| `makefile` | 43 | NEORV32 Docker 交叉编译 + `make local` 本地构建 |

### 编译结果

- **本地 GCC**: `gcc -DLOCAL_BUILD -Wall -O2` 零警告
- **Docker 交叉编译**: `riscv-none-elf-gcc` 零错误，text 段 **13,556 字节**（32KB IMEM 的 41%）
- **IMEM 镜像**: 由 `sw/build.sh app/crypto_cli` 生成到 `src/rtl/neorv32_imem_image.vhd`

### 已知待完成

- NEORV32 实板 bench（需 CSR_CYCLE + 上板烧录）
- TRNG 硬件随机性验证（需 DE2-115 实板）
- Zk* 内联汇编加速（当前为纯 C 参考实现，注释中已标注指令编码）
- `hex`/`led`/`clip`/`screen` 命令（Phase 3）
