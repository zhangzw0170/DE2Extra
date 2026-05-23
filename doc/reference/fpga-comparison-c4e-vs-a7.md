# Cyclone IV E vs Artix-7 资源对比

> 日期: 2026-05-23
> DE2-115: EP4CE115F29C7 | FFT 项目板: XC7A100TFGG484

## 核心资源

| 资源 | Cyclone IV E EP4CE115 | Artix-7 XC7A100T | 倍率 | 对 FFT 移植的影响 |
|---|---|---|---|---|
| **逻辑单元** | 114,480 LEs | 101,440 LUTs | 1.1:1 🟢 | 差不多，SDF 1.8K/14K 都装得下 |
| **DSP** | 266 (18×18) | 240 (DSP48E1, 25×18) | 1.1:1 🟢 | 数量略多，但 Artix DSP 是硬核级流水线 |
| **Block RAM** | 3,888 Kb = 486 KB | 4,860 Kb = 607 KB | 1:1.25 🟡 | Artix 多 25%，但 SDF 128 只需 ~8KB ROM |
| **PLL** | 4 | 6 (MMCM) | 1:1.5 | Artix 时钟灵活度更高 |
| **全局时钟** | 20 | 32 | 1:1.6 | 够用 |
| **最大用户 I/O** | 528 | 300 | 1.75:1 🟢 | DE2-115 引脚更多 |
| **工艺** | 60nm | 28nm | 2:1 🔴 | **Artix 快得多** |
| **FF 速度等级** | -7 (慢) | -2 (快) | ~2.5:1 | **这是最大的差异** |

## DSP 详解 — 最大差异点

| 特性 | Cyclone IV 18×18 | Artix-7 DSP48E1 |
|---|---|---|
| 乘法器 | 18×18 → 36-bit | 25×18 → 43-bit |
| 内置累加器 | ❌ 只有乘法 | ✅ 48-bit 累加器 |
| 流水线寄存器 | 输入端可选 | 输入/中间/输出全流水 |
| 单 DSP 做复数乘 | ❌ 需 4 个 DSP + 加法 | ✅ 1 个 DSP48 即可 |
| Fmax (乘法) | ~250 MHz (-7) | ~540 MHz (-2) |

**FFT 移植的关键影响**：Artix-7 上一个 DSP48E1 可以做一次 25×18 乘法 + 48-bit 累加 + 流水线，等于 Cyclone IV 上一个 18×18 乘法器裸奔——没有累加器、没有内部流水线寄存器。

SDF FFT 的复数乘法器在 Artix-7 消耗 3 个 DSP48E1，在 Cyclone IV 需 4 个 18×18 + 外部加法逻辑。DSP 数量翻倍，但 128 点 SDF 只需要 8 个 DSP（× 4 = 32 个），266 个总量完全够用。

## Block RAM 差异

| 特性 | Cyclone IV M9K | Artix-7 BRAM36 |
|---|---|---|
| 每块容量 | 9 Kb | 36 Kb |
| 块数 | 432 | 135 |
| 总容量 | 3,888 Kb | 4,860 Kb |
| 配置 | 单/双端口 | 真双端口 |
| Byte enable | ❌ | ✅ |

对 SDF 移植影响小——twiddle ROM 和 delay line buffer 都放得下。

## 速度等级对比

| 参数 | Cyclone IV -7 | Artix-7 -2 |
|---|---|---|
| 查找表延迟 | ~2.5ns | ~0.9ns |
| DSP 乘法延迟 | ~4ns | ~1.85ns |
| BRAM 访问 | ~3.5ns | ~1.5ns |
| 典型 Fmax (16-bit 逻辑) | ~200MHz | ~450MHz |

DE2-115 主频 50MHz → 我们完全不受速度限制。SDF 128 只需要 50MHz 就能实时跑 48KHz 音频 FFT，连 100MHz 都不用。

## FFT 移植估算

| 模块 | 原 Artix-7 资源 | Cyclone IV 等效 | 结论 |
|---|---|---|---|
| `fft_sdf_top` (128pt) | 1,802 LUTs + 8 DSP | ~2,500 LEs + 32 DSP | ✅ 轻松 |
| `complex_mult` | 3 DSP48E1 | 4 个 18×18 | ✅ 改封装 |
| `twiddle_rom` | 1 BRAM36 | 4 个 M9K | ✅ 分块 |
| delay line (shift reg) | SRL32 | 用寄存器或 M9K | ⚠️ 需改 |
| 全系统 (含 NEORV32+VGA) | — | ~9,000 LEs + 47 DSP | ✅ 78% LEs 空闲 |

## 结论

**能移植。唯一的坑是 Artix-7 的 SRL32 (移位寄存器原语) 在 Cyclone IV 不存在，需要用寄存器链或 M9K FIFO 替代。** SDF 架构里每个 stage 有一条可变长度延迟线，Artix-7 用 SRL32 高效实现，DE2-115 上需要用 slice 寄存器或 M9K 替代——面积会增加但 114K LEs 足够挥霍。

整体工作量：翻译 6 个 Verilog 文件 → VHDL，替换 SRL32 → 寄存器链，验证与 MATLAB 结果一致。约 **2-3 天**。
