# Phase 4: 音频 + SD 卡 (可选扩展)

> **计划执行时间: 2026-05-23 16:31** | **归档: 音频合并到 phase5-sdram-gui.md，SD 卡推迟**
> **已合并到 V3** — 音频部分已移至 `phase5-sdram-gui.md` (5.10 节)，SD 卡推迟到 6/15 后。本文档仅作历史参考。
>
> 日期: 2026-05-23 | 状态: Merged into V3
> 前提: Phase 2b (VGA+PS/2) 上板通后

## 本阶段概述

锦上添花的扩展。让 DE2-115 能播放音频，通过 SD 卡加载文件。不是为了赶 6/15 截止日期——做着玩的，能做完多少算多少。

---

## 4.1 音频子系统

### 硬件架构

```
CPU (NEORV32)                    DE2-115 板载
┌──────────┐                     ┌─────────────────┐
│ de2shell │── XBUS ──→ WM8731   │ WM8731 CODEC    │
│ audio.c  │          registers  │ ├─ I2C (配置)    │ → LINE_OUT
│          │── XBUS ──→ I2S TX   │ ├─ I2S (数据)    │ → HEADPHONE
└──────────┘                     │ └─ MCLK (18.432) │
                                 └─────────────────┘
```

### 需要新建的 VHDL 模块

| 模块 | 文件 | 功能 | 参考来源 |
|---|---|---|---|
| WM8731 控制器 | `src/rtl/periph/wm8731_ctrl.vhd` | I2C 主机 + WM8731 寄存器初始化 | Terasic `I2C_Controller.v` + `I2C_AV_Config.v` |
| I2S 发送器 | `src/rtl/periph/i2s_tx.vhd` | 16-bit 立体声 I2S 发送 | Terasic `AUDIO_DAC.v` (简化版) |
| PLL 音频时钟 | `clk_rst_gen.vhd` 修改 | 18.432MHz MCLK 输出 | PLL c2 输出 |

### 寄存器接口 (XBUS)

**WM8731 (0xF000C000)**:

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x00 | R | 状态: bit0=init_done, bit1=i2c_busy |
| 0x04 | W | 控制: bit0=reset, bit1=power_down |

**I2S TX (0xF000D000)**:

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x00 | W | 左声道数据 [15:0] |
| 0x04 | W | 右声道数据 [15:0] |
| 0x08 | R | 状态: bit0=fifo_empty, bit1=fifo_full |
| 0x0C | W | 控制: bit0=enable, bit1=loop_mode |

### WM8731 初始化序列

Terasic 已验证的寄存器值 (I2C 地址 0x34):

```
Reg 0x00: 0x001A  — Left Line In (0dB, enable)
Reg 0x02: 0x001A  — Right Line In
Reg 0x04: 0x007B  — Left Headphone Out (0dB, zero-cross enable)
Reg 0x06: 0x007B  — Right Headphone Out
Reg 0x08: 0x00F8  — Analog Path (DAC + bypass + sidetone)
Reg 0x0A: 0x0006  — Digital Path (no soft mute, no de-emphasis)
Reg 0x0C: 0x0000  — Power Down (all on, no power save)
Reg 0x0E: 0x0001  — Digital Format (I2S, 16-bit)
Reg 0x10: 0x0002  — Sampling Control (48KHz, normal mode)
Reg 0x12: 0x0001  — Active Control (activate)
```

### I2S 时序参数

| 参数 | 值 | 说明 |
|---|---|---|
| MCLK | 18.432 MHz | PLL 从 50MHz 生成 (50×18÷49 ≈ 18.367, 误差 0.35%) |
| Sample Rate | 48 KHz | LRCK = 48 KHz |
| BCK | 3.072 MHz | = 48K × 16 × 2 × 2 (双声道, 双沿) |
| Data Width | 16 bit | MSB first |

### C 软件 (de2shell 子程序)

`sw/app/de2shell/audio.c`:

- `init()`: 等待 WM8731 初始化完成，启用 I2S
- `update()`: 从音频缓冲区取数据，写入 I2S 寄存器
- 音频缓冲区: 循环缓冲，CPU 在 update 中填充
- 简单正弦波生成: 48-sample LUT (Terasic AUDIO_DAC.v 自带)

命令: `tone` (播放 440Hz 正弦波), `beep` (短提示音)

---

## 4.2 SD 卡子系统

### 硬件接口

DE2-115 SD 卡槽使用 SPI 模式 (4 线: CS, CLK, MOSI, MISO)。

**方案**: 纯 C 实现，使用 NEORV32 的 SPI 控制器 (bit-bang 也可)。不需要 VHDL。

### 软件层

| 文件 | 功能 | 参考 |
|---|---|---|
| `sd_spi.c` | SD SPI 初始化 + 扇区读写 | Terasic `sd_protocol.c` |
| `fat_fs.c` | FAT16/32 文件系统 (只读) | Terasic `FatFileSystem.c` |
| `sd_test.c` | de2shell 子程序: `ls`, `cat`, `play` | — |

### 文件列表

```
src/rtl/periph/
├── wm8731_ctrl.vhd       ← 新增: I2C + WM8731 初始化
└── i2s_tx.vhd            ← 新增: I2S 发送器

sw/app/de2shell/
├── audio.c               ← 新增: 音频播放子程序
├── sd_spi.c              ← 新增: SD SPI 驱动 (Phase 4b)
└── fat_fs.c              ← 新增: FAT 文件系统 (Phase 4b)
```

### 工作量估算

| 任务 | 时间 | 难度 |
|---|---|---|
| I2C 主机 VHDL (翻译 Terasic Verilog) | 2 小时 | 低 — 逐行翻译 |
| WM8731 配置序列 (翻译 LUT) | 1 小时 | 低 — 复制粘贴 |
| I2S 发送器 VHDL | 2 小时 | 低 — 50 行 VHDL |
| PLL 18.432MHz 配置 | 0.5 小时 | 低 — 改 PLL 参数 |
| audio.c 正弦波测试 | 1 小时 | 低 |
| SD SPI 驱动 (C) | 3 小时 | 中 — 移植 |
| FAT 文件系统 (C) | 3 小时 | 中 — 移植 |
| **总计** | **~12 小时** | — |

### 演示效果

- `tone` → 从 LINE_OUT 播放 440Hz 正弦波
- `beep` → 短提示音 (键盘按键反馈)
- 未来: SD 卡 WAV 播放

---

## 与已有模块的关系

Phase 4 是纯增量——不改动任何已有代码。

| 需要改动的 | 改动内容 |
|---|---|
| `de2extra_pkg.vhd` | 加 `ADDR_WM8731_BASE`, `ADDR_I2S_BASE` |
| `clk_rst_gen.vhd` | PLL 加 18.432MHz 输出 |
| `de2_115_top.vhd` | 实例化 wm8731_ctrl + i2s_tx |
| `wb_intercon.vhd` | 加 2 个 slave 端口 |
| `par/de2extra.qsf` | 加 VHDL_FILE + 引脚 (I2C_SCLK, I2C_SDAT, AUD_*) |
| `de2shell/main.c` | 注册 `audio` 子程序 |

---

## 优先级

音频优先级高于 SD 卡——音频能立刻演示 (一声响就有效果)，SD 卡需要 FAT 文件系统调试。

| 优先级 | 子任务 | 做它的理由 |
|---|---|---|
| **先做** | WM8731 控制器 + I2S 发送器 | 纯硬件，翻译 Terasic 代码即可，不依赖其他 |
| **次做** | audio.c 正弦波测试 | 验证硬件通路正确 |
| **最后** | SD SPI + FAT | 依赖多，调试复杂，6/15 后来得及 |
