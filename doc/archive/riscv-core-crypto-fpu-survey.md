# 开源 RISC-V 软核调研：Crypto ISA + FPU 对比

> 用于 DE2Extra / A7Pro CPU 选型决策
> 日期: 2026-05-22

## 带密码学 ISA 的开源 RISC-V 软核

### NEORV32 (当前使用)
- ISA: RV32IMC + Zicsr + Zicntr + Zfinx + Zkne + Zknd + Zknh + Zksed + Zksh + Zbkb + Zbkc + Zbkx
  - I: 基础整数 (37 指令)
  - M: 整数乘除法
  - C: 16 位压缩指令
  - F (Zfinx): 单精度浮点，**共用整数寄存器** (32 个 x 寄存器，无独立 f 寄存器)
  - Zkne: AES-128/256 加密 (aes32esmi, aes32esi)
  - Zknd: AES-128/256 解密 (aes32dsmi, aes32dsi)
  - Zknh: SHA-256/SHA-512 哈希 (sha256sum0/1, sha256sig0/1, sha512*)
  - Zksed: SM4 国密加密 (sm4ed, sm4ks0/1/2/3)
  - Zksh: SM3 国密哈希 (sm3p0, sm3p1)
  - Zbkb: 密码学位操作 (andn, orn, xnor, pack, brev8, rev8, zip, unzip, ror)
  - Zbkc: 无进位乘法 (clmul, clmulh)
  - Zbkx: 交叉排列 (xperm4, xperm8)
  - Zicsr: CSR 访问指令
  - Zicntr: 基础计数器 (cycle, time, instret)
- Crypto 覆盖: NIST 全套 (AES+SHA) + 国密全套 (SM4+SM3) + 位操作
- FPU: Zfinx 仅 (无 f 寄存器，IPC 受限)
- 语言: VHDL-2008
- 面积: ~2300 LUT @Cyclone IV, ~200 DSP
- 频率: 50MHz @Cyclone IV DE2-115 (fmax ~128MHz)
- 来源: https://github.com/stnolting/neorv32
- XCFU: 支持 Core-V eXtension Interface (cv-x-if)，可挂载外部协处理器

### VexRiscv
- ISA: RV32IM[A][F][D][C]
  - I: 基础整数
  - M: 整数乘除法
  - A: 原子操作 (LR/SC, AMO)
  - F: 单精度浮点 (32 位 IEEE 754, 独立 f 寄存器)
  - D: 双精度浮点 (64 位 IEEE 754)
  - C: 压缩指令
- Crypto: AesPlugin 仅 (AES 加速)，**无 Zknh/Zksed/Zksh**
- FPU: FpuPlugin，完整 IEEE 754 流水线
  - F32: ~2100 LUT, ~1780 FF @Artix-7 (FMax 205MHz)
  - F64: ~3700 LUT, ~3200 FF @Artix-7 (FMax 165MHz)
  - 支持非规格数 (subnormal)，异常标志，FMA
- 语言: SpinalHDL (生成 Verilog)
- 面积: CPU ~1500 LUT + FPU ~2100-3700 LUT
- 频率: ~200MHz
- DMIPS: 1.44 DMIPS/MHz
- 来源: https://github.com/SpinalHDL/VexRiscv

### FROST (Two Sigma)
- ISA: RV32GCB + Zbkb + B (Zba/Zbb/Zbs) + Zifencei + Zicond + Zihintpause
  - G = IMAFD: 基础整数 + 乘除法 + 原子操作 + 单精度浮点 + 双精度浮点
  - C: 压缩指令
  - B: Zba (地址生成) + Zbb (基础位操作) + Zbs (单位置位)
  - Zbkb: 密码学位操作 (仅这一个密码学扩展)
- Crypto: 仅 Zbkb (andn, orn, xnor, pack, brev8, clmul, clmulh) — **无 AES/SHA 硬件指令**
- FPU: 内置 FD (F32+F64 完整)
- 语言: SystemVerilog
- 面积: ~6500 LUT @Kintex-7 Genesys2
- 频率: 133MHz @Kintex-7, 300MHz @UltraScale+
- 6 级流水线 (IF/PD/ID/EX/MA/WB)，有 L0 cache + BTB + RAS
- 来源: https://github.com/twosigma/frost

### ChipForge MCU (Bittensor ChipForge 竞赛)
- ISA: RV32IMC + Zkne + Zknd + Zknh + Zbkb + Zbkc + Zbkx + Zbb
  - I: 基础整数
  - M: 整数乘除法
  - C: 压缩指令
  - Zkne: AES 加密
  - Zknd: AES 解密
  - Zknh: SHA-256
  - Zbkb/Zbkc/Zbkx: 位操作
  - Zbb: 基础位操作
  - 无 Zksed/Zksh (国密 SM4/SM3 不支持)
- FPU: 无
- 语言: SystemVerilog
- 用途: ASIC，非 FPGA 优化
- 来源: https://github.com/TatsuProject/chipforge-mcu

### Rocket Chip (UC Berkeley)
- ISA: RV64GC (64 位) — Zk* 可通过 TileLink RoCC 加速器添加
  - G = IMAFD (64 位)
  - C: 压缩
- Crypto: 需外部 RoCC 加速器，核心本身不集成
- FPU: 内置完整 FPU
- 语言: Chisel (生成 Verilog)
- 面积: ~27500 LUT/核 (64 位)
- 频率: ~100MHz @FPGA
- 来源: https://github.com/chipsalliance/rocket-chip

---

## FPU 方案

### 方案: NEORV32 + 外挂 FPnew (via XCFU/cv-x-if)
- NEORV32 保持不变，通过 XCFU 接口连接 PULP FPnew (fpu_ss)
- FPnew (openhwgroup/cvfpu):
  - 参数化，支持 F32/F64/F16/Half
  - 完整流水线 (1 result/cycle for add/sub/mul/fma)
  - IEEE 754-2008 兼容，支持非规格数
  - F32: ~3300 LUT (Artix-7)
  - F64: ~5300 LUT (Artix-7)
  - 语言: SystemVerilog
- 总面积: NEORV32 ~2300 + FPnew ~3300 = ~5600 LUT
- 优势: Crypto ISA 完整 + FPU 强大，NEORV32 已有代码零修改
- 风险: cv-x-if 集成工作量，FPnew 是 SystemVerilog 需适配

### 当前 Zfinx 性能问题
- Zfinx 共用整数寄存器，浮点操作需 save/restore 整数上下文
- 寄存器压力导致 IPC 下降 (NEORV32 文档估计约 -10% IPC)
- 单精度尚可，双精度几乎不可用 (需要 2 个整数寄存器存一个 f64)

---

## A7Pro 外设差异 (重要)

A7Pro 外设与 DE2-115 几乎完全不同：光纤接口、HDMI、ADC/DAC 等均不存在于 DE2-115。
- 平台无关设计仍然有效（外设控制器 VHDL 不变）
- 但顶层 (`xxx_top.vhd`)、引脚约束、PLL 需要全部重写
- 实际上 A7Pro 移植约等于新建一个平台项目，复用率仅限于 `src/rtl/periph/` 和 `src/rtl/bus/`

---

## ISA 扩展支持总览

| 扩展 | 全称 | NEORV32 | VexRiscv | FROST | ChipForge | Rocket |
|---|---|:---:|:---:|:---:|:---:|:---:|
| I | 基础整数 | ✅ | ✅ | ✅ | ✅ | ✅ |
| M | 整数乘除 | ✅ | ✅ | ✅ | ✅ | ✅ |
| C | 压缩指令 | ✅ | ✅ | ✅ | ✅ | ✅ |
| A | 原子操作 | - | ✅ | - | - | ✅ |
| F | 单精度浮点 | ✅ (Zfinx)¹ | ✅ | ✅ | - | ✅ |
| D | 双精度浮点 | - | ✅ | ✅ | - | ✅ |
| B | 位操作 | - | - | Zba+Zbb+Zbs | Zbb | - |
| **Zbkb** | 密码学位操作 | ✅ | - | ✅ | ✅ | - |
| **Zbkc** | 无进位乘法 | ✅ | - | - | ✅ | - |
| **Zbkx** | 交叉排列 | ✅ | - | - | ✅ | - |
| **Zkne** | AES 加密 | ✅ | (插件) | - | ✅ | - |
| **Zknd** | AES 解密 | ✅ | (插件) | - | ✅ | - |
| **Zknh** | SHA-256/512 | ✅ | - | - | ✅ | - |
| **Zksed** | SM4 国密 | ✅ | - | - | - | - |
| **Zksh** | SM3 国密 | ✅ | - | - | - | - |
| Zicsr | CSR 访问 | ✅ | ✅ | ✅ | ✅ | ✅ |
| Zicntr | 基础计数器 | ✅ | ✅ | ✅ | ✅ | ✅ |
| Zifencei | 指令栅栏 | - | - | ✅ | - | ✅ |
| Zicond | 条件零 | - | - | ✅ | - | ✅ |
| XCFU | 自定义指令 | ✅ (XCFU)² | - | - | - | ✅ (RoCC)² |

> ¹ **Zfinx**: 浮点扩展的变体，浮点数据存放在整数寄存器 x 中，无独立 f 寄存器。省面积但寄存器压力大，约 -10% IPC。标准 F 扩展有 32 个独立 f 寄存器，不占用整数寄存器。
> ² **XCFU / RoCC**: 两种不同的协处理器扩展接口。XCFU (Core-V eXtension Interface，即 cv-x-if) 由 OPENHWGROUP 定义，NEORV32 使用；RoCC (Rocket Custom Coprocessor) 由 UC Berkeley 定义，Rocket Chip 使用。两者功能类似但接口协议不同。

---

## 指令级对比 — 密码学扩展

### Zkne (AES 加密) — RV32 指令

| 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `aes32esi` | AES ShiftRows + InvShiftRows | ✅ | 插件 | - | ✅ |
| `aes32esmi` | AES MixColumns + InvMixColumns | ✅ | 插件 | - | ✅ |

### Zknd (AES 解密) — RV32 指令

| 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `aes32dsi` | AES InvShiftRows + ShiftRows | ✅ | 插件 | - | ✅ |
| `aes32dsmi` | AES InvMixColumns + MixColumns | ✅ | 插件 | - | ✅ |

### Zknh (SHA-2 哈希) — RV32 指令

| 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `sha256sum0` | SHA-256 Sigma0 | ✅ | - | - | ✅ |
| `sha256sum1` | SHA-256 Sigma1 | ✅ | - | - | ✅ |
| `sha256sig0` | SHA-256 Ch(x,y,e,f,g,h) | ✅ | - | - | ✅ |
| `sha256sig1` | SHA-256 Maj(x,y,z) | ✅ | - | - | ✅ |
| `sha512sum0r` | SHA-512 Sigma0 (低32) | ✅ | - | - | ✅ |
| `sha512sum1r` | SHA-512 Sigma1 (低32) | ✅ | - | - | ✅ |
| `sha512sig0h` | SHA-512 Sigma0 (高32) | ✅ | - | - | ✅ |
| `sha512sig0l` | SHA-512 Sigma0 (低32) | ✅ | - | - | ✅ |
| `sha512sig1h` | SHA-512 Maj (高32) | ✅ | - | - | ✅ |
| `sha512sig1l` | SHA-512 Maj (低32) | ✅ | - | - | ✅ |

### Zksed (SM4 国密) — RV32 指令

| 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `sm4ed` | SM4 单轮加密 | ✅ | - | - | - |
| `sm4ks0` | SM4 密钥扩展 r=0 | ✅ | - | - | - |
| `sm4ks1` | SM4 密钥扩展 r=1 | ✅ | - | - | - |
| `sm4ks2` | SM4 密钥扩展 r=2 | ✅ | - | - | - |
| `sm4ks3` | SM4 密钥扩展 r=3 | ✅ | - | - | - |

### Zksh (SM3 国密) — RV32 指令

| 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `sm3p0` | SM3 P0 压缩 | ✅ | - | - | - |
| `sm3p1` | SM3 P1 压缩 | ✅ | - | - | - |

### Zbkb (密码学位操作) — RV32 指令

| 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `andn` | AND 取反 | ✅ | - | ✅ | ✅ |
| `orn` | OR 取反 | ✅ | - | ✅ | ✅ |
| `xnor` | XNOR | ✅ | - | ✅ | ✅ |
| `pack` | 打包低半字 | ✅ | - | ✅ | ✅ |
| `packh` | 打包低字节 | ✅ | - | ✅ | ✅ |
| `packw` | 打包宽字 | ✅ | - | ✅ | ✅ |
| `brev8` | 字节位反转 | ✅ | - | ✅ | ✅ |
| `rev8` | 字节序交换 | ✅ | - | ✅ | ✅ |
| `zip` | 交叉压缩 | ✅ | - | ✅ | ✅ |
| `unzip` | 交叉解压 | ✅ | - | ✅ | ✅ |
| `orc.b` | OR-combine 字节 | ✅ | - | ✅ | ✅ |
| `clmul` | 无进位乘法 | ✅ | - | - | ✅ |
| `clmulh` | 无进位乘法 (高位) | ✅ | - | - | ✅ |

### Zbkc (无进位乘法) — RV32 指令

| 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `clmul` | 无进位乘法 (低位) | ✅ | - | - | ✅ |
| `clmulh` | 无进位乘法 (高位) | ✅ | - | - | ✅ |

### Zbkx (交叉排列) — RV32 指令

| 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `xperm4` | 4-bit 交叉排列 | ✅ | - | - | ✅ |
| `xperm8` | 8-bit 交叉排列 | ✅ | - | - | ✅ |

---

## 指令级对比 — B 位操作扩展

### Zba (地址生成) — RV32 指令

| 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `add.uw` | 无符号字加法 (忽略溢出) | - | - | ✅ | - |
| `slliu.w` | 逻辑左移 (立即数，32 位截断) | - | - | ✅ | - |
| `srliu.w` | 逻辑右移 (立即数，32 位截断) | - | - | ✅ | - |
| `rori` | 旋转右移 (立即数) | - | - | - | - |
| `roriw` | 旋转右移 (立即数，32 位截断) | - | - | - | - |
| `slli.uw` | 逻辑左移 (立即数，无符号字) | - | - | ✅ | - |
| `clz` | 前导零计数 | - | - | ✅ | - |
| `ctz` | 后导零计数 | - | - | ✅ | - |
| `cpop` | 总体位计数 | - | - | ✅ | - |
| `min` | 有符号最小 | - | - | ✅ | - |
| `max` | 有符号最大 | - | - | ✅ | - |
| `minu` | 无符号最小 | - | - | ✅ | - |
| `maxu` | 无符号最大 | - | - | ✅ | - |
| `sext.b` | 符号扩展字节 | - | - | ✅ | - |
| `sext.h` | 符号扩展半字 | - | - | - | - |
| `zext.h32` | 零扩展半字到 32 位 | - | - | - | - |

### Zbb (基础位操作) — RV32 指令

| 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `andn` | AND 取反 | ✅ (Zbkb) | - | ✅ (Zbkb) | ✅ (Zbkb) |
| `orn` | OR 取反 | ✅ (Zbkb) | - | ✅ (Zbkb) | ✅ (Zbkb) |
| `xnor` | XNOR | ✅ (Zbkb) | - | ✅ (Zbkb) | ✅ (Zbkb) |
| `clzw` | 字前导零 | - | - | ✅ | - |
| `ctzw` | 字后导零 | - | - | ✅ | - |
| `cpopw` | 字总体计数 (字) | - | - | - | - |
| `rol` | 旋转左移 (寄存器) | - | - | ✅ | - |
| `rolw` | 旋转左移 (字) | - | - | ✅ | - |
| `ror` | 旋转右移 (寄存器) | - | - | ✅ (Zbkb) | ✅ (Zbkb) |
| `rorw` | 旋转右移 (字) | - | - | - | - |
| `sh1add` | x + (x << 1) | - | - | ✅ | - |
| `sh2add` | x + (x << 2) | - | - | ✅ | - |
| `sh3add` | x + (x << 3) | - | - | ✅ | - |
| `sh1add.uw` | 同上，无符号字 | - | - | ✅ | - |
| `sh2add.uw` | 同上，无符号字 | - | - | ✅ | - |
| `sh3add.uw` | 同上，无符号字 | - | - | ✅ | - |
| `slliu.w` | 逻辑左移 (立即数，32 位截断) | - | - | ✅ (Zba) | - |
| `orc.b` | OR-combine 字节 | ✅ (Zbkb) | - | ✅ (Zbkb) | ✅ (Zbkb) |
| `brev8` | 字节位反转 | ✅ (Zbkb) | - | ✅ (Zbkb) | ✅ (Zbkb) |

### Zbs (单位置位) — RV32 指令

| 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `bclr` | 位清除 | - | - | ✅ | - |
| `bclri` | 位清除立即 | - | - | ✅ | - |
| `binv` | 位反转 | - | - | ✅ | - |
| `bext` | 位提取 | - | - | ✅ | - |
| `bexti` | 位提取立即 | - | - | ✅ | - |

---

## 指令级对比 — 浮点扩展

### F (单精度浮点) — RV32 指令

| 指令 | 功能 | NEORV32 (Zfinx) | VexRiscv (F) | FROST (F) | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `flw` | 加载浮点到 f 寄存器 | — (用 `lw`) | ✅ | ✅ | - |
| `fsw` | 从 f 寄存器存储浮点 | — (用 `sw`) | ✅ | ✅ | - |
| `fmadd.s` | 融合乘加 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fmsub.s` | 融合乘减 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fnmsub.s` | 取负融合乘减 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fnmadd.s` | 取负融合乘加 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fadd.s` | 浮点加 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fsub.s` | 浮点减 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fmul.s` | 浮点乘 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fdiv.s` | 浮点除 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fsqrt.s` | 浮点平方根 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fmin.s` | 浮点最小 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fmax.s` | 浮点最大 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `feq.s` | 浮点等于比较 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `flt.s` | 浮点小于比较 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fle.s` | 浮点小于等于比较 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fclass.s` | 浮点分类 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fmv.x.w` | f→x 寄存器复制 | — (已在 x 中) | ✅ | ✅ | - |
| `fmv.w.x` | x→f 寄存器复制 | — (已在 x 中) | ✅ | ✅ | - |
| `fsgnj.s` | 符号注入 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fsgnjn.s` | 取负符号注入 | ✅ (x 寄存器) | ✅ | ✅ | - |
| `fsgnjx.s` | 异或符号注入 | ✅ (x 寄存器) | ✅ | ✅ | - |

> 注: Zfinx 中浮点数据直接存放在整数寄存器 x 中，因此 `flw`/`fsw` 不存在（改用普通 `lw`/`sw`），`fmv.x.w`/`fmv.w.x` 也不需要（数据已在 x 寄存器中）。算术指令编码不变，但操作数和结果使用 x 寄存器而非 f 寄存器。

### D (双精度浮点) — RV32 指令

| 指令 | 功能 | NEORV32 | VexRiscv (D) | FROST (D) | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `fld` | 加载双精度 | - | ✅ | ✅ | - |
| `fsd` | 存储双精度 | - | ✅ | ✅ | - |
| `fmadd.d` | 融合乘加 | - | ✅ | ✅ | - |
| `fmsub.d` | 融合乘减 | - | ✅ | ✅ | - |
| `fnmsub.d` | 取负融合乘减 | - | ✅ | ✅ | - |
| `fnmadd.d` | 取负融合乘加 | - | ✅ | ✅ | - |
| `fadd.d` | 双精度加 | - | ✅ | ✅ | - |
| `fsub.d` | 双精度减 | - | ✅ | ✅ | - |
| `fmul.d` | 双精度乘 | - | ✅ | ✅ | - |
| `fdiv.d` | 双精度除 | - | ✅ | ✅ | - |
| `fsqrt.d` | 双精度平方根 | - | ✅ | ✅ | - |
| `fmin.d` | 双精度最小 | - | ✅ | ✅ | - |
| `fmax.d` | 双精度最大 | - | ✅ | ✅ | - |
| `feq.d` | 双精度等于 | - | ✅ | ✅ | - |
| `flt.d` | 双精度小于 | - | ✅ | ✅ | - |
| `fle.d` | 双精度小于等于 | - | ✅ | ✅ | - |
| `fclass.d` | 双精度分类 | - | ✅ | ✅ | - |
| `fmv.x.d` | int→double 转换 | - | ✅ | ✅ | - |
| `fmv.d.x` | double→int 转换 | - | ✅ | ✅ | - |
| `fcvt.s.d` | double→single 转换 | - | ✅ | ✅ | - |
| `fcvt.d.s` | single→double 转换 | - | ✅ | ✅ | - |
| `fcvt.w.s` | single→int 转换 | - | ✅ | ✅ | - |
| `fcvt.w.d` | double→int 转换 | - | ✅ | ✅ | - |
| `fcvt.wu.s` | single→uint 转换 | - | ✅ | ✅ | - |
| `fcvt.wu.d` | double→uint 转换 | - | ✅ | ✅ | - |
| `fcvt.s.w` | int→single 转换 | - | ✅ | ✅ | - |
| `fcvt.s.wu` | uint→single 转换 | - | ✅ | ✅ | - |
| `fcvt.d.w` | int→double 转换 | - | ✅ | ✅ | - |
| `fcvt.d.wu` | uint→double 转换 | - | ✅ | ✅ | - |

> 注: NEORV32 不支持 D 扩展（无独立 f 寄存器，Zfinx 只能在 x 寄存器中放 32 位 float，无法存储 64 位 double）。VexRiscv/FROST 通过独立 f 寄存器支持 FD。

---

## 指令级对比 — A 扩展

| 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge |
|---|---|:---:|:---:|:---:|:---:|
| `lr.w` | 链接加载 | - | ✅ | - | - |
| `sc.w` | 条件存储 | - | ✅ | - | - |
| `amoswap.w` | 原子交换 | - | ✅ | - | - |
| `amoadd.w` | 原子加 | - | ✅ | - | - |
| `amosub.w` | 原子减 | - | ✅ | - | - |
| `amoand.w` | 原子与 | - | ✅ | - | - |
| `amoor.w` | 原子或 | - | ✅ | - | - |
| `amoxor.w` | 原子异或 | - | ✅ | - | - |
| `amomin.w` | 原子有符号最小 | - | ✅ | - | - |
| `amomax.w` | 原子有符号最大 | - | ✅ | - | - |
| `amominu.w` | 原子无符号最小 | - | ✅ | - | - |
| `amomaxu.w` | 原子无符号最大 | - | ✅ | - | - |

---

## 指令级对比 — 其他扩展

| 扩展 | 指令 | 功能 | NEORV32 | VexRiscv | FROST | ChipForge | Rocket |
|---|---|---|:---:|:---:|:---:|:---:|:---:|
| Zicsr | `csrrw` `csrrs` `csrcr` `csrrwi` `csrrsi` `csrcci` | CSR 读写 | ✅ | ✅ | ✅ | ✅ | ✅ |
| Zicntr | `rdcycle` `rdtime` `rdinstret` | 读硬件计数器 | ✅ | ✅ | ✅ | ✅ | ✅ |
| Zifencei | `fence.i` | 指令排序栅栏 | - | - | ✅ | - | ✅ |
| Zicond | `czero.eqz` `czero.nez` | 条件零 | - | - | ✅ | - | ✅ |
| XCFU/RoCC | 自定义 | 可扩展协处理器 | ✅ (XCFU) | - | - | - | ✅ (RoCC) |
| Debug | `dret` `ebreak` | 调试 | ✅ | ✅ | - | - | ✅ |
| CLINT | `mret` `wfi` `ecall` | 特权级 | ✅ | ✅ | ✅ | - | ✅ |

---

## 性能对比 (待实际跑分)

| 指标 | NEORV32 @50MHz | NEORV32 @100MHz | NEORV32 + FPnew | FROST @133MHz | VexRiscv @200MHz | 80486DX2-66 |
|---|---|---|---|---|---|---|---|
| DMIPS | ~50 | ~95 | ~85 (FPU 开销) | ~170 | ~288 | ~40 |
| AES (硬件) | 有 | 有 | 有 | 无 | 部分 | 无 |
| SHA (硬件) | 有 | 有 | 有 | 无 | 无 | 无 |
| SM4/SM3 | 有 | 有 | 有 | 无 | 无 | 无 |
| FPU | Zfinx 弱 | Zfinx 弱 | FPnew 强 | FD 强 | FD 强 | x87 强 |
| 面积 | ~2300 LUT | ~2300 LUT | ~5600 LUT | ~6500 LUT | ~3600 LUT | ASIC |

> 注: DMIPS 数据除 FROST 外均来自各项目官方数据，FROST 为估算。需实际跑 CoreMark 验证。
