# V3 Phase 4b: 音频合成器 -- 双轨 PS/2 键盘合成器 (3xOSC + DX7 FM)

> 日期: 2026-05-25 | 状态: 设计阶段
> 目标板: DE2-115 (Cyclone IV E EP4CE115F29C7), WM8731 音频编解码器
> 集成: NEORV32 Wishbone 外设 @ 0xF0013000 (新地址)
> 参考: `doc/audio-synth-design.md` (完整设计文档)

---

## 1. 概述

实现一个双轨硬件合成器，通过 PS/2 键盘实时演奏。PS/2 键盘分为两个区域，分别控制左右声道的独立音高：

- **Track 1** (左声道): 主键盘区 (Q-P / A-L / Z-M 行)
- **Track 2** (右声道): 数字小键盘区 (Num0-9, *, -, +, Enter)

两种合成模式可软件切换：

| 模式 | 原理 | 听感 | 复杂度 |
|------|------|------|--------|
| **3xOSC** (加法合成) | 3 个 DDS 振荡器叠加，独立波形/八度/微调/音量 | 丰富音色，类似 FL Studio 3xOSC | 低 |
| **DX7** (FM 合成) | 调制器正弦波调制载波频率，对数域零乘法器 | 金属感/电子音，经典 Yamaha DX7 | 中 |

音频输出通过板载 WM8731 DAC，I2S 接口，48kHz 16-bit 立体声。配置通过 I2C 完成。

### 地址规划说明

原始设计文档 (`doc/audio-synth-design.md`) 和阶段计划 (`phase5-sdram-gui.md` Section 11) 均标注地址为 0xF000B000。但实际代码中该地址已被 LCD 控制器 (`lcd_wb`) 占用 (`de2extra_pkg.vhd` 中 `ADDR_LCD_BASE = 0xF000B000`)。wb_intercon 当前 s0-s10 全部占用：

| Slave | 地址 | 外设 |
|-------|------|------|
| s0 | 0x01000000 | SDRAM |
| s1 | 0xF0000000 | VGA |
| s2 | 0xF0008000 | PS/2 |
| s3 | 0xF000C000 | IR |
| s4 | 0xF000F000 | NTT |
| s5 | 0xF000B000 | **LCD** |
| s6 | 0xF0009000 | Timer |
| s7 | 0xF000A000 | INTC |
| s8 | 0xF0010000 | ExpDemo |
| s9 | 0xF0011000 | PONG |
| s10 | 0xF0012000 | Conway |

**最终地址: 0xF0013000** -- 在 wb_intercon 中新增 s11 端口，de2extra_pkg 新增 `ADDR_SYNTH_BASE`。

---

## 2. 硬件模块清单

所有 VHDL 文件位于 `src/rtl/periph/`，除非另有说明。

### 2.1 wm8731_ctrl.vhd -- I2C 配置控制器

上电自动通过 I2C 配置 WM8731 的 10 个寄存器。配置完成后拉高 `ready` 信号。

| 项目 | 说明 |
|------|------|
| 时钟域 | 50 MHz |
| I2C 从机地址 | 0x34 (7-bit: 0x1A << 1) |
| I2C 时钟 | ~20 KHz (50MHz / 2500) |
| 状态机 | IDLE -> START -> ADDR -> REG_ADDR -> DATA -> STOP -> DONE |
| 输出 | `i2c_sclk_o`, `i2c_sdat_o`, `ready_o` |

WM8731 寄存器配置序列 (来自 DE2-115-Synthesizer 参考设计):

| 寄存器 | 值 | 说明 |
|--------|-----|------|
| 0x00 | 0x1A | Left Line In, -6dB |
| 0x01 | 0x1A | Right Line In, -6dB |
| 0x02 | 0x7B | Left Headphone, 0dB |
| 0x03 | 0x7B | Right Headphone, 0dB |
| 0x04 | 0xF8 | Analog: DAC on, LINE in, MIC off |
| 0x05 | 0x06 | Digital: 16-bit, I2S mode |
| 0x06 | 0x00 | Power: all on |
| 0x07 | 0x01 | Format: I2S, 16-bit, slave mode |
| 0x08 | 0x02 | Sample: 48KHz, 256x MCLK |
| 0x09 | 0x01 | Active: activate codec |

### 2.2 i2s_tx.vhd -- I2S 发送器

接收左右声道各 16-bit 采样数据，按 I2S 协议串行发送给 WM8731。

| 项目 | 说明 |
|------|------|
| 时钟域 | 50 MHz (内部同步 BCLK/LRCK) |
| 工作模式 | WM8731 slave mode: FPGA 提供数据，WM8731 生成 BCLK/LRCK |
| 输入 | `bclk_i` (WM8731 生成), `lrck_i` (WM8731 生成) |
| 输出 | `dacdat_o` (串行音频数据, MSB first) |
| 接口 | 内部 32-bit 移位寄存器 (16-bit L + 16-bit R) |
| 数据来源 | 从合成引擎读取当前采样的 L/R 数据 |

**注意**: WM8731 在 slave 模式下生成 BCLK 和 LRCK，FPGA 只需要提供 MCLK (AUD_XCK) 和串行 DAC 数据。

### 2.3 dds_core.vhd -- DDS 核心振荡器

每个 Track 在 3xOSC 模式下实例化 3 个 DDS 核心。

| 项目 | 说明 |
|------|------|
| 相位累加器 | 32-bit |
| 采样率 | 48 kHz |
| 频率控制字 | TW = (f_note * 2^32) / 48000 |
| 波形选择 | 4 种 (sine/square/sawtooth/triangle) |
| 八度偏移 | TW << octave_shift (硬件左移) |
| 微调 (detune) | 近似乘法: TW * (1 + cents * 0.000578) |

**A4 (440Hz) 频率控制字**: TW = 39,276,827 (0x0257EEDB)

**MIDI 音符频率控制字**: 预计算查找表 (88 个音符, A0=21 到 C8=108)，存放在 C 固件中。软件写入 TW 到寄存器，硬件不需要知道 MIDI 编号。

### 2.4 波表 ROM (内含于 synth_engine 或独立 MIF)

256 entry x 16-bit signed, 存储在单个 M9K block RAM 中。总大小 1024 x 16 = 16,384 bits = 2 M9K。

| 地址范围 | 波形 | 描述 |
|----------|------|------|
| 0x000-0x0FF | Sine | 正弦波, Q15 格式 |
| 0x100-0x1FF | Square | 方波 (0x7FFF / 0x8000) |
| 0x200-0x2FF | Sawtooth | 锯齿波 (-32768 到 +32767 线性) |
| 0x300-0x3FF | Triangle | 三角波 |

地址线 [9:8] 选择波形，[7:0] 为相位索引。可复用现有 `DDS_ROM.vhd` 的 1024-entry 架构（当前 `DDS_ROM.vhd` 是 1024x10bit 正弦波，需重新生成 MIF）。

**MIF 文件**: `src/rtl/periph/wavetable_4wave.mif` (Python 生成脚本: `src/rtl/periph/gen_wavetable.py`)

### 2.5 fm_operator.vhd -- FM 合成算子 (DX7 模式)

基于 OPL3 FPGA 参考设计的对数域计算方法，零 DSP 乘法器。

```
1. phase_acc += phase_inc           (32-bit 相位累加)
2. theta = phase_acc[31:24]         (8-bit 正弦地址, 256 entry)
3. log_sin = log_sine_LUT[theta]    (256x12 ROM)
4. level = log_sin + envelope       (log 域加法 = 线性域乘法)
5. output = exp_LUT[level & 0xFF] << (15 - (level >> 8))
```

**子模块 (可内联)**:

| 模块 | 大小 | 说明 |
|------|------|------|
| log_sine_LUT | 256 x 12-bit (~1 M9K) | 正弦波对数域表示 |
| exp_LUT | 256 x 10-bit (~1 M9K) | 对数到幅度转换 |
| phase_generator | ~50 LEs | 相位累加 + LUT 查找 |
| envelope_generator | ~80 LEs | ADSR 包络状态机 |

**ADSR 包络参数**:

| 参数 | 位宽 | 说明 |
|------|------|------|
| AR (Attack Rate) | 4-bit | 0-15, 包络从 511 递减到 0 的速率 |
| DR (Decay Rate) | 4-bit | 0-15, 包络从 0 递增到 SL 的速率 |
| SL (Sustain Level) | 4-bit | 0-15, 持续电平 |
| RR (Release Rate) | 4-bit | 0-15, 按键释放后包络递增到 511 (静音) 的速率 |

内部包络计数器: 9-bit (0 = 最大音量, 511 = 静音)。

### 2.6 synth_engine.vhd -- 合成器顶层 (Wishbone slave)

顶层实体，包含所有子模块，通过 Wishbone 总线接受 CPU 控制。

```
synth_engine.vhd (Wishbone slave @ 0xF0013000)
├── wm8731_ctrl (I2C 配置, 上电自动初始化)
├── i2s_tx (I2S 发送器)
├── dds_core x 6 (3xOSC 模式: 每轨 3 个 DDS 振荡器)
│   └── wavetable ROM (256x16bit x 4 波形, M9K)
├── fm_operator x 4 (DX7 模式: 每轨 2 个 FM 算子)
│   ├── log_sine_LUT (256x12)
│   └── exp_LUT (256x10)
├── mode_mux (3xOSC / DX7 输出选择)
├── mixer (饱和加法, L + R)
└── wb_registers (Wishbone 寄存器文件)
```

---

## 3. 寄存器接口 (0xF0013000)

所有寄存器为 32-bit 宽度，字对齐 (偏移为 4 的倍数)。

### 3.1 全局控制

| 偏移 | R/W | 位域 | 默认值 | 说明 |
|------|-----|------|--------|------|
| 0x00 | R/W | [0] | 0 | 全局静音 (1=mute) |
| | | [2:1] | 00 | 合成模式 (00=3xOSC, 01=DX7, 10/11=保留) |
| | | [4:3] | 00 | 主音量 (0=最大, 3=-12dB) |
| | | [31:5] | 0 | 保留 |
| 0x04 | R | [0] | - | WM8731 就绪 (I2C 初始化完成) |
| | | [1] | - | 保留 |

### 3.2 Track 1 (左声道 -- 主键盘区)

| 偏移 | R/W | 位域 | 说明 |
|------|-----|------|------|
| 0x08 | W | [7:0] | MIDI 音符 (0=释放, 21=A0, 60=C4, 108=C8) |
| | | [31:8] | 保留 |
| 0x0C | W | [1:0] | OSC1 波形 (00=sin, 01=square, 10=saw, 11=tri) |
| | | [3:2] | OSC1 八度偏移 (00=基频, 01=+1, 10=+2, 11=-1) |
| | | [15:8] | OSC1 音量 (0-255, 255=最大) |
| | | [31:16] | 保留 |
| 0x10 | W | [1:0] | OSC2 波形 |
| | | [3:2] | OSC2 八度偏移 |
| | | [15:8] | OSC2 音量 |
| | | [31:16] | 保留 |
| 0x14 | W | [1:0] | OSC3 波形 |
| | | [3:2] | OSC3 八度偏移 |
| | | [15:8] | OSC3 音量 |
| | | [31:16] | 保留 |
| 0x18 | W | [7:0] | DX7: 调制器频率比 (0=0.5x, 1=1x, 2=2x, 3=3x, 4=4x) |
| | | [15:8] | DX7: 调制指数 (0=纯 sine, 127=最强 FM) |
| | | [31:16] | 保留 |
| 0x1C | W | [3:0] | DX7: AR (Attack rate, 0-15) |
| | | [7:4] | DX7: DR (Decay rate, 0-15) |
| | | [11:8] | DX7: SL (Sustain level, 0-15) |
| | | [15:12] | DX7: RR (Release rate, 0-15) |
| | | [31:16] | 保留 |

### 3.3 Track 2 (右声道 -- 数字小键盘区)

| 偏移 | R/W | 说明 |
|------|-----|------|
| 0x24 | W | Track 2 MIDI 音符 (同 0x08 布局) |
| 0x28 | W | Track 2 OSC1 (同 0x0C 布局) |
| 0x2C | W | Track 2 OSC2 (同 0x10 布局) |
| 0x30 | W | Track 2 OSC3 (同 0x14 布局) |
| 0x34 | W | Track 2 DX7 ratio/index (同 0x18 布局) |
| 0x38 | W | Track 2 DX7 ADSR (同 0x1C 布局) |

### 3.4 C 驱动宏定义

```c
#define SYNTH_BASE   ((volatile uint32_t *)0xF0013000)

#define SYNTH_CTRL   SYNTH_BASE[0]   // 0x00: 全局控制
#define SYNTH_STATUS SYNTH_BASE[1]   // 0x04: 状态 (只读)

// Track 1 (左声道)
#define SYNTH_T1_NOTE SYNTH_BASE[2]  // 0x08
#define SYNTH_T1_OSC1 SYNTH_BASE[3]  // 0x0C
#define SYNTH_T1_OSC2 SYNTH_BASE[4]  // 0x10
#define SYNTH_T1_OSC3 SYNTH_BASE[5]  // 0x14
#define SYNTH_T1_DX7_RI SYNTH_BASE[6] // 0x18: ratio + index
#define SYNTH_T1_DX7_ADSR SYNTH_BASE[7] // 0x1C

// Track 2 (右声道)
#define SYNTH_T2_NOTE SYNTH_BASE[9]  // 0x24
#define SYNTH_T2_OSC1 SYNTH_BASE[10] // 0x28
#define SYNTH_T2_OSC2 SYNTH_BASE[11] // 0x2C
#define SYNTH_T2_OSC3 SYNTH_BASE[12] // 0x30
#define SYNTH_T2_DX7_RI SYNTH_BASE[13] // 0x34
#define SYNTH_T2_DX7_ADSR SYNTH_BASE[14] // 0x38
```

---

## 4. PS/2 键盘映射

软件层 (C) 负责将 PS/2 Set 2 扫描码映射为 MIDI 音符号。扫描码以 make code (按下) 和 break code (0xF0 + make, 释放) 形式到达。

### 4.1 Track 1 -- 主键盘区 (左声道)

映射为钢琴白键 + 黑键布局。默认八度 = 4。

```
  ┌────┬────┬────┬────┬────┬────┬────┬────┬────┬────┐
  │ Q  │ W  │ E  │ R  │ T  │ Y  │ U  │ I  │ O  │ P  │  <- 黑键
  │C#4 │D#4 │    │F#4 │G#4 │A#4 │    │C#5 │D#5 │    │
  ├────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
  │ A  │ S  │ D  │ F  │ G  │ H  │ J  │ K  │ L  │ ;  │  <- 白键
  │ C4 │ D4 │ E4 │ F4 │ G4 │ A4 │ B4 │ C5 │ D5 │ D5 │
  └────┴────┴────┴────┴────┴────┴────┴────┴────┴────┘
  Tab = 八度 -1, CapsLock = 八度 +1
```

**扫描码映射表 (Set 2 make code -> MIDI 音符号, 默认八度 4):**

| 按键 | Set 2 Make Code | MIDI 音符号 | 音名 |
|------|-----------------|-------------|------|
| A | 0x1C | 60 | C4 |
| W | 0x1D | 61 | C#4 |
| S | 0x1B | 62 | D4 |
| E | 0x24 | 63 | D#4 |
| D | 0x23 | 64 | E4 |
| F | 0x2B | 65 | F4 |
| R | 0x2D | 66 | F#4 |
| G | 0x34 | 67 | G4 |
| T | 0x33 | 68 | G#4 |
| H | 0x2C | 69 | A4 |
| Y | 0x15 | 70 | A#4 |
| J | 0x35 | 71 | B4 |
| K | 0x3B | 72 | C5 |
| I | 0x2C | 73 | C#5 |
| L | 0x3B | 74 | D5 |
| O | 0x12 | 75 | D#5 |
| ; (semicolon) | 0x3C | 76 | E5 |

**注**: 部分扫描码需要实际验证。Set 2 扫描码可能与键盘具体型号有关。上表基于标准 PS/2 Set 2 码表，实现时需要对照实际键盘确认。

**八度切换**:

| 按键 | Set 2 Make Code | 功能 |
|------|-----------------|------|
| Tab | 0x0D | 当前八度 -1 |
| CapsLock | 0x58 | 当前八度 +1 |

**按键释放**: 收到 0xF0 前缀后，下一个扫描码对应释放事件，写入音符号 0 表示释放。

### 4.2 Track 2 -- 数字小键盘区 (右声道)

默认八度 = 4 (与 Track 1 独立)。

```
  ┌────┬────┬────┬────┐
  │ NL │ /  │ *  │ -  │  <- NumLock, 除, 乘, 减
  │    │    │    │    │
  ├────┼────┼────┼────┤
  │ 7  │ 8  │ 9  │ +  │  <- C4, D4, E4, 八度+1
  ├────┼────┼────┤    │
  │ 4  │ 5  │ 6  │    │  <- F4, G4, A4
  ├────┼────┼────┼────┤
  │ 1  │ 2  │ 3  │ EN │  <- B3, C4, D4, 八度-1
  ├────┼────┼────┤    │
  │ 0  │ .  │    │    │  <- E3, F3
  └────┴────┴────┴────┘
  NumLock = 八度切换
```

**扫描码映射表 (Set 2 make code -> MIDI 音符号):**

| 按键 | Set 2 Make Code | MIDI 音符号 | 音名 |
|------|-----------------|-------------|------|
| Num 7 | 0x6C | 72 | C5 |
| Num 8 | 0x75 | 74 | D5 |
| Num 9 | 0x7D | 76 | E5 |
| Num / | 0x4A | 77 | F5 |
| Num 4 | 0x6B | 65 | F4 |
| Num 5 | 0x73 | 67 | G4 |
| Num 6 | 0x74 | 69 | A4 |
| Num * | 0x7C | 72 | C5 |
| Num 1 | 0x69 | 71 | B4 |
| Num 2 | 0x72 | 60 | C4 |
| Num 3 | 0x7A | 62 | D4 |
| Num - | 0x7A | 64 | E4 |
| Num 0 | 0x70 | 59 | B3 |
| Num . | 0x71 | 65 | F4 |
| Num Enter | 0x5A | 67 | G4 |
| Num + | 0x79 | 69 | A4 |
| NumLock | 0x77 | (八度切换) | -- |

**注**: 数字小键盘的扫描码同样需要实际键盘验证。NumLock 开启/关闭状态下扫描码不同 -- 本设计假设 NumLock 开启状态。

### 4.3 MIDI 音符号到频率控制字转换

软件端预计算查找表 (C 固件中):

```c
// f = 440.0 * pow(2.0, (note - 69) / 12.0)
// TW = (uint32_t)((double)f * 4294967296.0 / 48000.0)

static const uint32_t tuning_table[88] = {
    /* 21: A0  */ 0x00370ACC,  // 27.5 Hz
    /* 22: A#0 */ 0x003C2D15,
    /* 23: B0  */ 0x004184DA,
    /* ... (完整 88 个音符) ... */
    /* 60: C4  */ 0x0257EEDB,  // 261.63 Hz
    /* 69: A4  */ 0x0257EEDB * 2 = 0x04AFDDB6,  // 440 Hz (实际需预计算)
    /* ... */
    /* 108: C8 */ 0x257EEDB0,  // 4186 Hz
};
```

Python 生成脚本在 C 驱动源文件中用注释说明，或写成 `gen_tuning_table.py`。

---

## 5. 实现步骤

### Step 1: WM8731 I2C 初始化 + I2S 发送 -- 播放 440Hz 正弦波测试

**目标**: 最小可验证 -- 上板后耳机能听到 440Hz 正弦波。

**VHDL 工作**:
1. 新建 `src/rtl/periph/wm8731_ctrl.vhd`: I2C 主机 FSM + 10 寄存器配置序列
2. 新建 `src/rtl/periph/i2s_tx.vhd`: I2S 发送器 (PISO 移位寄存器)
3. 新建 `src/rtl/periph/synth_engine.vhd`: 最简框架 -- 只含 I2C + I2S + 硬编码 440Hz 正弦波
4. Python 脚本生成 `wavetable_4wave.mif` (256x16 x 4 波形)

**RTL 修改**:
1. `de2extra_pkg.vhd`: 新增 `ADDR_SYNTH_BASE = 0xF0013000`
2. `wb_intercon.vhd`: 新增 s11 端口 (5-bit 地址, 4KB 空间)
3. `de2os_top.vhd`: 新增 AUD_XCK/AUD_BCLK/AUD_DACLRCK/AUD_DACDAT/I2C_SCLK/I2C_SDAT 引脚声明; 实例化 synth_engine
4. `clk_rst_gen.vhd`: 新增 PLL 输出 18.432 MHz (或使用 WM8731 内部 PLL 模式降低要求)
5. `par/de2os/de2os.qsf`: 新增 VHDL 文件 + 引脚分配

**引脚分配**:
```
set_location_assignment PIN_E1 -to AUD_XCK
set_location_assignment PIN_F2 -to AUD_BCLK
set_location_assignment PIN_E3 -to AUD_DACLRCK
set_location_assignment PIN_D1 -to AUD_DACDAT
set_location_assignment PIN_B7 -to I2C_SCLK
set_location_assignment PIN_A8 -to I2C_SDAT
```

**验证**: 仿真 I2C 写时序 + I2S 数据输出。上板后用示波器/耳机确认 440Hz 输出。

**预估工时**: 3h

### Step 2: 单 DDS 振荡器 -- CPU 写频率寄存器播放

**目标**: CPU 通过 Wishbone 写入频率控制字，播放不同音高。

**VHDL 工作**:
1. 新建 `src/rtl/periph/dds_core.vhd`: 32-bit 相位累加器 + 波表 ROM 地址生成
2. 扩展 synth_engine: 增加单轨 DDS 通道，Wishbone 寄存器写入 TW
3. 波表 ROM 集成到 synth_engine 内部 (M9K block RAM, altsyncram IP)

**C 驱动**:
1. 新建 `sw/app/de2shell_rtos/synth.c`: 基本音符播放函数
2. `midi_to_tuning_word()` 转换函数
3. `synth test` 命令: 播放音阶 (C4-C5)

**验证**: 仿真 DDS 相位累加 + 波表输出。上板播放 C 大调音阶。

**预估工时**: 1.5h

### Step 3: PS/2 键盘映射

**目标**: 主键盘区按键实时发出对应音高。

**C 工作**:
1. `synth.c`: 实现 scan_code -> MIDI 音符查找表 (Track 1)
2. 在 `t_uart_input` 任务中增加 PS/2 合成器模式: 收到扫描码后查表写 SYNTH_T1_NOTE
3. Tab/CapsLock 八度切换
4. Break code (0xF0) 处理: 写 0 释放音符

**命令**: `synth` 启动合成器模式, `synth off` 退出。

**验证**: 上板, 按键盘弹奏 C 大调。

**预估工时**: 1h

### Step 4: 双轨分轨

**目标**: 主键盘 = Track 1 (左声道), 数字小键盘 = Track 2 (右声道)。

**VHDL 工作**:
1. 扩展 synth_engine: 双轨 DDS 通道
2. I2S 发送器支持立体声 (交替发送 L/R)
3. 混音器: 每轨独立输出

**C 工作**:
1. Track 2 扫描码 -> MIDI 音符查找表 (数字小键盘)
2. 双轨独立八度切换
3. 双轨同时按键测试

**验证**: 仿真立体声 I2S 输出。上板左手右手同时弹奏。

**预估工时**: 1.5h

### Step 5: 3xOSC 模式

**目标**: 每轨 3 个独立振荡器叠加，独立波形/八度/音量控制。

**VHDL 工作**:
1. dds_core 实例化 x6 (每轨 3 个)
2. 每个振荡器独立相位累加器 + 波表 ROM (共享 ROM, 地址线多路选择)
3. 混音器: 6 路 16-bit 有符号数饱和加法
4. 音量控制: 乘法 (可移位近似: sample * vol / 256)
5. 八度偏移: TW 左移/右移
6. 微调 (detune): 硬件近似或省略 (Phase 5 再实现)

**寄存器**: OSC1/OSC2/OSC3 各自的波形、八度、音量寄存器已定义 (0x0C/0x10/0x14, 0x28/0x2C/0x30)。

**C 驱动**: `synth preset` 命令加载预设音色 (e.g., "pad" = 3 个微失谐正弦波, "bass" = 基频 + 低八度方波)。

**验证**: 仿真 3 个振荡器混音输出。上板切换音色预设。

**预估工时**: 1.5h

### Step 6: DX7 FM 模式

**目标**: 每轨 2-op FM 合成，对数域零乘法器。

**VHDL 工作**:
1. 新建 `src/rtl/periph/fm_operator.vhd`: 相位累加 + log_sine_LUT 查找 + exp_LUT 转换 + ADSR 包络
2. log_sine_LUT ROM: 256 x 12-bit (MIF 文件, 从 OPL3 FPGA 参考提取)
3. exp_LUT ROM: 256 x 10-bit (同上)
4. ADSR 包络状态机: 4 状态 (ATTACK/DECAY/SUSTAIN/RELEASE), 9-bit 内部计数器
5. synth_engine 中实例化 4 个 fm_operator (每轨 modulator + carrier)
6. FM 连接: modulator 输出加到 carrier 相位上
7. mode_mux: 根据 SYNTH_CTRL[2:1] 选择 3xOSC 或 DX7 输出

**寄存器**: DX7 ratio/index/ADSR 寄存器已定义 (0x18/0x1C, 0x34/0x38)。

**C 驱动**: `synth fm` 命令切换到 DX7 模式, `synth fm preset` 加载 FM 预设。

**验证**: 仿真 FM 算子输出波形。上板切换 3xOSC/DX7 模式对比听感。

**预估工时**: 2h

### Step 7 (可选): 打磨与优化

1. ADSR 包络参数调优
2. 音色预设保存/加载
3. 音量混音平衡
4. LFO (颤音) -- 可选
5. 滤波器 -- 可选

**预估工时**: 1h

**总预估工时**: ~10.5h (不含可选 Step 7)

---

## 6. WM8731 引脚表 (DE2-115)

来源: DE2-115 用户手册 + DE2-115-Synthesizer 参考设计。需对照 `DE2-115引脚表.xlsx` 确认。

| FPGA 信号 | DE2-115 引脚 | WM8731 引脚 | 方向 | 说明 |
|-----------|-------------|-------------|------|------|
| AUD_XCK | PIN_E1 | MCLK (11) | OUT | 主时钟, 18.432 MHz |
| AUD_BCLK | PIN_F2 | BCLK (7) | IN | I2S 位时钟 (WM8731 生成, slave 模式) |
| AUD_DACLRCK | PIN_E3 | LRCOUT (9) | IN | I2S 左右声道选择 (WM8731 生成) |
| AUD_DACDAT | PIN_D1 | DACDAT (8) | OUT | I2S DAC 串行数据 |
| AUD_ADCDAT | PIN_D2 | ADCDAT (3) | IN | ADC 数据 (暂不接) |
| AUD_ADCLRCK | PIN_C2 | LRCIN (6) | IN | ADC LRCK (暂不接) |
| I2C_SCLK | PIN_B7 | SCL (16) | OUT | I2C 配置时钟 |
| I2C_SDAT | PIN_A8 | SDA (15) | BIDIR | I2C 配置数据 (开漏) |

**WM8731 工作模式**: Slave mode -- FPGA 提供主时钟 (MCLK) 和串行 DAC 数据, WM8731 内部生成 BCLK 和 LRCK。

**I2C 总线**: 标准 I2C, SDA 需要外部上拉电阻 (DE2-115 板上已有)。

**重要**: 引脚分配必须在写入 QSF 前对照 `DE2-115引脚表.xlsx` 二次确认。错误引脚可以编译通过但硬件不工作。

---

## 7. 资源估算

| 模块 | LEs | M9K | DSP | 说明 |
|------|-----|-----|-----|------|
| wm8731_ctrl (I2C) | ~200 | 0 | 0 | I2C FSM + 配置序列 ROM |
| i2s_tx (I2S 发送) | ~150 | 0 | 0 | PISO 移位寄存器 + 分频 |
| dds_core x 6 (3xOSC) | ~300 | 2 | 0 | 32-bit 累加器 x 6 + 波表 ROM (1024x16) |
| fm_operator x 4 (DX7) | ~400 | 2 | 0 | log/exp LUT (各 256-entry) + 相位 + ADSR |
| mode_mux + mixer | ~100 | 0 | 0 | 多路选择 + 饱和加法 |
| wb_registers | ~150 | 0 | 0 | ~16 个寄存器 + 地址解码 |
| **合计** | **~1,300** | **~4** | **0** | -- |

**板载资源**:

| 资源 | 合成器占用 | 板载总量 | 占比 |
|------|-----------|---------|------|
| LEs | ~1,300 | 114,480 | 1.1% |
| M9K | ~4 | 432 | 0.9% |
| DSP | 0 | 532 | 0% |

与 de2os 当前编译结果 (8,125 LEs, ~30 M9K) 合计后: ~9,425 LEs (8.2%), ~34 M9K (7.9%), 仍在充裕范围内。

---

## 8. Quartus 工程修改清单

### 8.1 新增 VHDL 文件

```
src/rtl/periph/wm8731_ctrl.vhd
src/rtl/periph/i2s_tx.vhd
src/rtl/periph/dds_core.vhd
src/rtl/periph/fm_operator.vhd
src/rtl/periph/synth_engine.vhd
src/rtl/periph/wavetable_4wave.mif   (或 .hex)
```

### 8.2 QSF 新增

```tcl
set_global_assignment -name VHDL_FILE [file path]wm8731_ctrl.vhd
set_global_assignment -name VHDL_FILE [file path]i2s_tx.vhd
set_global_assignment -name VHDL_FILE [file path]dds_core.vhd
set_global_assignment -name VHDL_FILE [file path]fm_operator.vhd
set_global_assignment -name VHDL_FILE [file path]synth_engine.vhd
```

### 8.3 QSF 引脚分配

```tcl
set_location_assignment PIN_E1 -to AUD_XCK
set_location_assignment PIN_F2 -to AUD_BCLK
set_location_assignment PIN_E3 -to AUD_DACLRCK
set_location_assignment PIN_D1 -to AUD_DACDAT
set_location_assignment PIN_B7 -to I2C_SCLK
set_location_assignment PIN_A8 -to I2C_SDAT
```

### 8.4 de2extra_pkg.vhd 修改

```vhdl
constant ADDR_SYNTH_BASE : std_logic_vector(31 downto 0) := x"F0013000"; -- 4KB
```

### 8.5 wb_intercon.vhd 修改

新增 s11 端口: 5-bit 地址, 连接到 0xF0013000。

### 8.6 de2os_top.vhd 修改

1. 新增端口: AUD_XCK, AUD_BCLK, AUD_DACLRCK, AUD_DACDAT, I2C_SCLK, I2C_SDAT
2. 新增 synth Wishbone 信号声明
3. 实例化 synth_engine
4. wb_intercon 新增 s11 连接

### 8.7 clk_rst_gen.vhd 修改 (可能)

新增 PLL 输出: 18.432 MHz 或使用 WM8731 内部 PLL 模式 (寄存器 0x08 bit[2]=1) 允许更宽松的 MCLK 范围。需评估 Cyclone IV E PLL 能否精确生成 18.432 MHz。如果不能，使用 WM8731 内部 PLL 模式生成 12.288 MHz (48kHz x 256) 或 11.2896 MHz (44.1kHz x 256)。

---

## 9. 软件文件清单

| 文件 | 位置 | 说明 |
|------|------|------|
| synth.c | sw/app/de2shell_rtos/synth.c | 合成器 C 驱动 |
| synth.h | sw/app/de2shell_rtos/synth.h | 合成器头文件 |
| gen_wavetable.py | src/rtl/periph/gen_wavetable.py | 波表 MIF 生成脚本 |
| gen_tuning_table.py | sw/app/de2shell_rtos/gen_tuning_table.py | 音频频率控制字表生成 (可选) |

### C 驱动关键接口

```c
// synth.h
void synth_init(void);                    // 等待 WM8731 ready, 设置默认音色
void synth_note(uint8_t track, uint8_t midi_note); // 发送音符 (0=释放)
void synth_set_osc(uint8_t track, uint8_t osc, uint8_t wave, uint8_t octave, uint8_t vol);
void synth_set_dx7(uint8_t track, uint8_t ratio, uint8_t index, uint8_t ar, uint8_t dr, uint8_t sl, uint8_t rr);
void synth_set_mode(uint8_t mode);         // 0=3xOSC, 1=DX7
void synth_set_mute(uint8_t mute);        // 1=mute, 0=unmute
```

---

## 验收表

| 编号 | 验收项 | 状态 |
|------|--------|------|
| V3P4B.S1.1 | wm8731_ctrl.vhd I2C 写时序正确 (10 个寄存器配置完成, ready 拉高) | |
| V3P4B.S1.2 | i2s_tx.vhd I2S 输出正确 (MSB first, 16-bit, L/R 交替, 48kHz) | |
| V3P4B.S1.3 | 上板播放 440Hz 正弦波测试音 (WM8731 初始化成功, 耳机/示波器可验证) | |
| V3P4B.S2.1 | dds_core.vhd 单 DDS 振荡器仿真: 相位累加器 + 波表输出正确 | |
| V3P4B.S2.2 | CPU 写频率寄存器播放不同音高 (C 大调音阶, 频率准确) | |
| V3P4B.S3.1 | PS/2 主键盘区扫描码 -> MIDI 音符映射正确 (Tab/CapsLock 八度切换) | |
| V3P4B.S3.2 | Break code (0xF0) 正确释放音符 (写 0 到音符寄存器) | |
| V3P4B.S4.1 | 双轨分轨: Track 1 -> 左声道, Track 2 -> 右声道 | |
| V3P4B.S4.2 | 数字小键盘区扫描码 -> MIDI 音符映射正确 | |
| V3P4B.S4.3 | 双轨同时按键, 左右声道独立音高 | |
| V3P4B.S5.1 | 3xOSC 模式: 每轨 3 个振荡器独立波形/八度/音量控制 | |
| V3P4B.S5.2 | 混音器饱和加法, 无溢出爆音 | |
| V3P4B.S6.1 | fm_operator.vhd 仿真: 对数域 FM 调制波形正确 | |
| V3P4B.S6.2 | DX7 FM 模式: ADSR 包络可调 (AR/DR/SL/RR 寄存器有效) | |
| V3P4B.S6.3 | DX7 FM 模式: 调制指数/ratio 参数有效 (听感差异可辨) | |
| V3P4B.S6.4 | 软件可切换 3xOSC / DX7 模式 | |
| V3P4B.S7.1 | 波形正确性: 正弦波 THD < 5% (仿真 FFT 分析) | |
| V3P4B.S7.2 | 频率精度: A4=440Hz 误差 < 0.1% (仿真频率计) | |
| V3P4B.S7.3 | 主音量控制有效 (4 档) | |
| V3P4B.S7.4 | 全局静音功能有效 | |
| V3P4B.S8.1 | de2os 编译通过 (无新增时序违例) | |
| V3P4B.S8.2 | 资源占用: LEs < 1,500, M9K < 5 | |
