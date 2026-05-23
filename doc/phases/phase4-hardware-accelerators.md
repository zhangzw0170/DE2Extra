# Phase 4: 硬件加速器 + 音频

> 日期: 2026-05-23 | 状态: Planning
> 前提: Phase 2b (VGA+PS/2) 上板, Phase 1 (wb_intercon) 稳定

## 本阶段概述

从纯软件转向软硬件混合——利用 FPGA 的并行计算能力做 CPU 做不到的事。三个硬件加速器加一套音频通路，全部跑在 DE2-115 剩余的 107K LEs 和 250+ DSPs 上。

---

## 资源预算 (全系统)

| 模块 | LEs | DSP | M9K | 状态 |
|---|---|---|---|---|
| NEORV32 + VGA + PS/2 + SDRAM (Phase 1-3) | ~5,000 | ~15 | ~56 | ✅ 已规划 |
| **Conway 硬件引擎** | ~500 | 0 | ~1 | 🆕 |
| **PONG 硬件引擎** | ~800 | 0 | 0 | 🆕 |
| **NTT 加速器 (256pt)** | ~2,000 | ~64 | ~4 | 🆕 |
| Audio I2C + I2S | ~300 | 0 | 0 | 🆕 |
| **合计预估** | **~8,600** | **~79** | **~61** | — |
| 板载资源 | 114,480 | 266 | 432 | — |
| 占用率 | **7.5%** | **29.7%** | **14.1%** | ✅ 充裕 |

---

## 4.1 Conway 生命游戏硬件引擎

### 设计

纯硬件 B3/S23 计算 + 双缓冲 VGA 输出。CPU 只做初始化图案和暂停/继续控制。

```
┌──────────┐     ┌──────────────┐     ┌──────────┐
│ 当前网格  │ ──→ │ 邻居计数+规则 │ ──→ │ 下一网格  │
│ BRAM A   │     │ 8读 1写流水线 │     │ BRAM B   │
└──────────┘     └──────────────┘     └──────────┘
       ↑              │                     │
       └──── 交换 ────┘                     ↓
                                       VGA 像素映射
```

### 规格

| 参数 | 值 |
|---|---|
| 网格 | 80×25 (匹配 VGA 字符终端) |
| 规则 | B3/S23 |
| 边界 | 环面 (wrap-around) |
| 计算延迟 | 25 时钟/代 (每时钟一行) |
| @50MHz | ~20 ns/代 — 每秒 5000 万代 |
| CPU 交互 | 写寄存器: `glider/gun/random/clear/start/pause` |

### 寄存器接口 (0xF000F000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x00 | W | 命令: 0=clear, 1=glider, 2=gun, 3=random |
| 0x04 | R/W | 控制: bit0=enable, bit1=pause, bit2=single_step |
| 0x08 | R | 代数计数器 [31:0] |

### 文件

| 文件 | 说明 |
|---|---|
| `conway_engine.vhd` | 网格 BRAM + 邻居计数 + 规则逻辑 |
| `conway_vga.vhd` | VGA 像素映射 (cell → block char) |

### 与 C 版本的关系

C 版本 (`life.c`) 保留用于 UART 终端演示。硬件版本是 VGA 频道，通过 IR 遥控器切换。

---

## 4.2 PONG 硬件引擎

### 设计

经典双人 PONG，纯硬件 VGA 渲染。

```
  ← paddle L      ball (x,y,vx,vy)      paddle R →
  (PS/2 W/S)                           (PS/2 ↑/↓)
```

### 规格

| 参数 | 值 |
|---|---|
| 分辨率 | 640×480 像素区域 |
| 球 | 8×8 像素方块, 硬件碰撞检测 |
| 球拍 | 8×40 像素, PS/2 键盘控制位置 |
| 得分 | 硬件计数器, VGA 数字显示 |
| 物理 | 反弹角取决于击球位置 |

### 像素管线

```
h_count, v_count → 球拍碰撞? → 球位置? → 得分区? → 输出 RGB
```

零 BRAM——纯组合逻辑 + 少量寄存器。球的位置是寄存器，不是帧缓冲。

### 寄存器接口 (0xF000E000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x00 | W | 左球拍位置 [8:0] (PS/2 W/S) |
| 0x04 | W | 右球拍位置 [8:0] (PS/2 ↑/↓) |
| 0x08 | R | 得分: [15:8]=左, [7:0]=右 |
| 0x0C | W | 控制: bit0=reset, bit1=pause |

### 文件

| 文件 | 说明 |
|---|---|
| `pong_engine.vhd` | 球物理 + 碰撞检测 + 得分 |
| `pong_vga.vhd` | VGA 像素输出 (球拍、球、中线、得分) |

---

## 4.3 NTT 加速器

### 背景

Number Theoretic Transform — FFT 在有限域上的类比，Kyber/Dilithium 等后量子密码的核心运算。完美结合 DE2Extra 的密码学主题和 FFT 项目的 DSP 经验。

### 为什么 NTT 在 DE2-115 上特别合适

| 特性 | FFT | NTT |
|---|---|---|
| 数据类型 | float32 或 Q3.12 | **12-bit 整数** |
| 复数乘 | 4 DSP / 1 DSP48E1 | **1 个 18×18 DSP** |
| 256 点蝶形 | ~512 DSP (全并行) | **~128 DSP (全并行)** |
| 精度 | 每级累积误差 | **精确 (有限域)** |
| 旋转因子 ROM | sin/cos | ω^k mod q |

### 架构: SDF (Single-path Delay Feedback)

复用 FFT 项目的 SDF 架构，做 NTT 版本。

```
input → [BF stage0] → [×ω₀] → [delay N/2] → [BF stage1] → ... → bit-rev → output
          butterfly     ROM                shift reg
```

### 规格

| 参数 | 值 |
|---|---|
| 模数 | q = 3329 (Kyber 推荐, 12-bit 素数) |
| 点数 | 128 或 256 |
| 数据宽度 | 12-bit 输入, 12-bit 输出 |
| 蝶形运算 | (a+b, (a-b)×ω mod q) |
| 模乘 | 12×12 → 24-bit → Barrett reduction → 12-bit |
| 延迟线 | 可变长移位寄存器 (SRL32 → 寄存器链) |
| DSP 用量 | ~64 (256 点, 8 级, 每级 ~8 DSP) |

### 寄存器接口 (0xF000G000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x000-0x1FF | W | 输入数据 (128 × 16-bit words) |
| 0x200-0x3FF | R | 输出数据 (128 × 16-bit words) |
| 0x400 | W | 控制: bit0=start, bit1=dir (0=Fwd, 1=Inv) |
| 0x404 | R | 状态: bit0=busy, bit1=done |
| 0x408 | R | 周期数计数器 [31:0] |

### 软件演示

```
rv32> ntt demo
=== NTT Accelerator (q=3329, N=256) ===
Input:  [0x000, 0x001, ..., 0x0FF]
Computing... done (256 clocks @50MHz = 5.12 μs)
NTT:    [0x3A2, 0x1F4, ..., 0x0C8]
INTT:   [0x000, 0x001, ..., 0x0FF]  ✓ verified

Performance:  5.12 μs hardware
vs RISC-V C:  ~50 ms (9,766× speedup)
```

### 文件

| 文件 | 说明 |
|---|---|
| `ntt_top.vhd` | 顶层: 控制状态机 + 输入/输出 buffer |
| `ntt_stage.vhd` | 单级: butterfly + twiddle multiply + delay line |
| `ntt_butterfly.vhd` | (a+b, (a-b)×ω mod q) |
| `ntt_modmul.vhd` | 模乘: 12×12 → Barrett reduction |
| `ntt_twiddle_rom.vhd` | 旋转因子 ROM (预计算 ω^k mod q) |

### 与 FFT 项目的复用

| FFT_SDF 模块 | NTT 改写 |
|---|---|
| `complex_mult.v` | → `ntt_modmul.v` (只做实数模乘, 更简单) |
| `complex_addsub.v` | → `ntt_butterfly.v` (只做整数加减 mod q) |
| `fft_sdf_stage.v` | → `ntt_stage.v` (结构完全相同) |
| `twiddle_rom.v` | → `ntt_twiddle_rom.v` (ROM 内容改为 ω^k) |
| `bit_reverse.v` | → 直接复用 |

---

## 4.4 音频子系统 (保留)

与初版 Phase 4 计划相同: I2C 配置 WM8731 + I2S 双声道发送。优先级降为次于三大硬件加速器。

详见 `phase4-audio-sdcard.md` 原文档。

---

## 4.5 SD 卡子系统 (推迟)

推迟到 6/15 后。不再列入 Phase 4。

---

## 文件列表

```
src/rtl/periph/ (新增)
├── conway_engine.vhd       # Conway 硬件引擎
├── conway_vga.vhd          # Conway VGA 像素映射
├── pong_engine.vhd         # PONG 物理引擎
├── pong_vga.vhd            # PONG VGA 像素输出
├── ntt_top.vhd             # NTT 顶层
├── ntt_stage.vhd           # NTT 单级
├── ntt_butterfly.vhd       # NTT 蝶形
├── ntt_modmul.vhd          # 模乘
├── ntt_twiddle_rom.vhd     # 旋转因子 ROM
├── wm8731_ctrl.vhd         # I2C + WM8731 初始化
└── i2s_tx.vhd              # I2S 发送器

sw/app/de2shell/ (新增)
├── ntt_demo.c              # NTT 加速器演示子程序
└── audio.c                 # 音频播放子程序
```

---

## 工作量估算

| 模块 | 时间 | 难度 | 依赖 |
|---|---|---|---|
| Conway 硬件引擎 | 4 小时 | 低 | 纯新写, VGA 时序已有 |
| PONG 硬件引擎 | 4 小时 | 低 | 纯新写, VGA 时序已有 |
| NTT 模块 | 8 小时 | 中 | 翻译 FFT 项目的 SDF 架构 |
| 音频 I2C + I2S | 3 小时 | 低 | 翻译 Terasic Verilog |
| C 软件 (ntt_demo, audio) | 3 小时 | 低 | de2shell 框架已有 |
| 联调 | 4 小时 | 中 | — |
| **总计** | **~26 小时** | — | — |

---

## 优先级

| 顺序 | 模块 | 理由 |
|---|---|---|
| **1** | Conway 硬件引擎 | 最简, 500 LEs, 1 个下午出效果 |
| **2** | PONG | 比 Conway 稍复杂, 紧接着做 |
| **3** | NTT 加速器 | 最有技术含量, 复用 FFT 架构 |
| **4** | 音频 I2C + I2S | 等三者跑通后加音频 |
