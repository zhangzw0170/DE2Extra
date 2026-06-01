# 音频合成器设计文档 — 双轨 PS/2 键盘合成器 (3xOSC + DX7 FM)

> **NOTE: Address 0xF000B000 is now occupied by LCD (lcd_wb). The proposed synth address is 0xF0013000 (new s13 port). See doc/phases/v3p4b.md for the current plan.**
>
> 日期: 2026-05-25 | 状态: 设计阶段
> 目标板: DE2-115 (Cyclone IV E EP4CE115F29C7), WM8731 音频编解码器
> 集成: NEORV32 Wishbone 外设 @ 0xF0013000 (proposed; old address 0xF000B000 is now LCD)

---

## 1. 概述

实现一个双轨硬件合成器，通过 PS/2 键盘实时演奏：
- **Track 1** (左声道): 主键盘区 (Q-P / A-L / Z-M)
- **Track 2** (右声道): 数字小键盘区 (0-9, *, -, +, Enter)

两种合成模式可软件切换：
- **3xOSC 模式**: 3 个 DDS 振荡器叠加 (FL Studio 风格)
- **DX7 模式**: FM 频率调制合成 (Yamaha DX7 简化版)

---

## 2. 开源参考

### 2.1 DE2-115-Synthesizer (同板参考)

- **仓库**: https://github.com/masonparrish/DE2-115-Synthesizer
- **平台**: DE2-115 + WM8731 + PS/2 键盘 (Verilog)
- **许可**: Terasic 参考设计

**可移植模块:**

| 模块 | 功能 | 移植策略 |
|------|------|----------|
| `adio_codec.v` | 3 通道 DDS + 波形 LUT + 混音 + I2S 输出 | 移植为 VHDL, 包装为 Wishbone slave |
| `I2C_AV_Config.v` | WM8731 寄存器初始化序列 (10 个寄存器) | 提取音频部分 (索引 0-9), 移植为 VHDL |
| `I2C_Controller.v` | I2C 主机 FSM (24-bit 写事务) | 移植为 VHDL |
| `wave_gen_sin/brass/string/square.v` | 64-entry 波形查找表 | 升级为 256-entry M9K block RAM |

**不移植:**
- `ps2_keyboard.v` — 已有 `ps2_controller.vhd`, 软件层做按键追踪更灵活
- `AUDIO_DAC.v` — 被 `adio_codec.v` 取代, 仅参考 I2S 时钟分频模式

**WM8731 I2C 配置 (来自 I2C_AV_Config.v):**

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

**I2C 参数:**
- 从机地址: 0x34 (7-bit: 0x1A, 左移)
- I2C 时钟: ~20 KHz (从 50MHz 分频)
- 传输完成后触发 `I2C_END` 信号

**adio_codec.v 核心架构:**

```
18.432 MHz MCLK
       |
  BCK 分频器 (18.432M / 24 = 768 KHz... 不对)
  LRCK 分频器 (48 KHz)
       |
  每通道 DDS:
    16-bit 相位累加器 (+ sound_inc / LRCK cycle)
    ramp[15:10] → 波表 ROM → 16-bit 采样
       |
  混音: music1 + music2 + music3
       |
  PISO 移位寄存器 (MSB first, 16 bits)
       |
  AUD_BCK, AUD_LRCK, AUD_DACDAT → WM8731
```

### 2.2 OPL3 FPGA (DX7 FM 参考)

- **仓库**: https://github.com/gtaylormb/opl3_fpga
- **平台**: ZYBO (Zynq), SSM2603 DAC (SystemVerilog)
- **许可**: LGPL-3.0
- **星数**: 399

**核心 FM 算法:**

OPL3 使用 **对数域计算**, 不需要任何乘法器:

```
1. phase_acc += phase_inc           (20-bit 相位累加)
2. theta = phase_acc[9:2]           (8-bit 正弦地址)
3. log_sin = log_sine_LUT[theta]    (256×12 ROM)
4. level = log_sin + envelope       (log 域加法 = 线性域乘法!)
5. output = exp_LUT[level]          (256×10 ROM, 对数→幅度)
```

**FM 调制:**
```
carrier_output = exp( log_sin(phase_carrier + modulation_index * modulator_output) )
```
调制值直接加到载波相位上。

**ADSR 包络 (完整实现):**
- 4 状态: ATTACK → DECAY → SUSTAIN → RELEASE
- 9-bit 内部包络计数器 (0=最响, 511=静音)
- 全局 13-bit eg_timer 控制包络速率
- KSR (key scale rate) 调制
- KSL (key scale level) + TL (total level) + tremolo

**波形选择 (8 种, ws[2:0]):**
- 0: Sine, 1: Half-sine, 2: Abs-sine, 3: Quarter-sine
- 4: Sine/2, 5: Abs-sine/2, 6: Square, 7: Sine-staircase

**简化方案 — 不移植完整 OPL3, 只提取 4 个核心模块:**

| OPL3 模块 | 作用 | 保留? |
|-----------|------|-------|
| `opl3_log_sine_lut.sv` | 正弦波 log 域表示 (256×12 ROM) | **是** |
| `opl3_exp_lut.sv` | 对数→幅度转换 (256×10 ROM) | **是** |
| `phase_generator.sv` | 相位累加 + log-sine 查找 + exp 转换 | **是** |
| `envelope_generator.sv` | 完整 ADSR 状态机 | **是** |
| `calc_phase_inc.sv` | 频率增量计算 | 简化 (去除 vibrato) |
| `calc_envelope_shift.sv` | 包络速率缩放 | 简化 |
| `ksl_add_rom.sv` | Key scale level | 可选 (硬编码 KSL=0) |
| `vibrato.sv` / `tremolo.sv` | LFO | 可选 (初期去除) |
| `control_operators.sv` | 36 算子时分复用 | **去除** |
| `channels.sv` | 18 通道累加 | **去除** |
| `host_if.sv` | OPL2 寄存器协议 | **去除** (用 WB 寄存器替代) |

**简化架构 (4 个独立算子实例):**

```
fm_synth_top
  ├── track0_modulator: phase_gen + envelope_gen + calc_phase_inc
  ├── track0_carrier:    phase_gen + envelope_gen + calc_phase_inc
  │     (modulation = track0_modulator.out)
  ├── track1_modulator: phase_gen + envelope_gen + calc_phase_inc
  ├── track1_carrier:    phase_gen + envelope_gen + calc_phase_inc
  │     (modulation = track1_modulator.out)
  ├── mode_mux:         3xOSC 输出 / DX7 输出 选择
  ├── sum_and_clamp:    L/R 混音, 饱和截断到 16-bit
  └── i2s_tx:           WM8731 I2S 发送器
```

---

## 3. 硬件架构

### 3.1 顶层模块划分

```
synth_engine.vhd (Wishbone slave, 顶层)
├── wm8731_ctrl.vhd (I2C 配置, 上电自动初始化)
├── i2s_tx.vhd (I2S 发送器)
├── dds_core.vhd × 6 (3xOSC: 每轨 3 个 DDS 振荡器)
│   └── 波表 ROM (256×16, M9K block RAM)
├── fm_operator.vhd × 4 (DX7: 每轨 2 个 FM 算子)
│   ├── phase_generator (log-sine + exp LUT)
│   └── envelope_generator (ADSR)
├── mode_mux (3xOSC / DX7 输出选择)
├── mixer (饱和加法)
└── wb_registers (Wishbone 寄存器文件)
```

### 3.2 时钟需求

| 时钟 | 频率 | 用途 | 来源 |
|------|------|------|------|
| clk_50 | 50 MHz | NEORV32 CPU + Wishbone | 现有 PLL |
| AUD_XCK | 18.432 MHz | WM8731 主时钟 (MCLK) | **需新增 PLL 输出** |
| I2C_CLK | ~20 KHz | I2C 配置时钟 | 50MHz 分频 |

**PLL 修改**: `clk_rst_gen.vhd` 需新增 18.432 MHz 输出。DE2-115 有 50MHz 输入，PLL 可生成 18.432 MHz (可能存在微小频率偏差)。

**替代方案**: 使用 WM8731 的内部 PLL 模式 (寄存器 0x08 的 bit[2]=1)，允许 MCLK 为 11.2896-12.288 MHz 范围内的任意频率，这样可以用 PLL 精确生成。

### 3.3 WM8731 引脚

| FPGA 信号 | DE2-115 引脚 | WM8731 | 方向 |
|-----------|-------------|--------|------|
| AUD_XCK | PIN_E1 | MCLK | OUT |
| AUD_BCLK | PIN_F2 | BCLK | IN (slave) |
| AUD_DACLRCK | PIN_E3 | LRCK | IN (slave) |
| AUD_DACDAT | PIN_D1 | DACDAT | OUT |
| AUD_ADCDAT | PIN_D2 | ADCDAT | IN (暂不接) |
| AUD_ADCLRCK | PIN_C2 | ADCLRCK | IN (暂不接) |
| I2C_SCLK | PIN_B7 | SCL | OUT |
| I2C_SDAT | PIN_A8 | SDA | BIDIR |

**WM8731 slave 模式**: BCLK 和 LRCK 由 WM8731 内部生成，FPGA 只需提供 MCLK。

### 3.4 I2S 时序 (slave 模式)

```
MCLK = 18.432 MHz (256 × 48kHz)
BCLK = MCLK / 4 = 4.608 MHz (96 × 48kHz)
LRCK = BCLK / 64 = 72 kHz... 不对

标准 I2S:
  MCLK = 256 × fs
  BCLK = 64 × fs (16-bit × 2 channels)
  LRCK = fs = 48 kHz

48kHz: MCLK = 12.288 MHz, BCLK = 3.072 MHz
```

**注意**: 实际 MCLK 频率取决于 PLL 能精确生成什么值。18.432 MHz 是 Terasic 原设计的值，对应特定分频比。

---

## 4. Wishbone 寄存器接口 (0xF0013000)

### 4.1 全局控制

| 偏移 | R/W | 位域 | 说明 |
|------|-----|------|------|
| 0x00 | R/W | [0] | 全局静音 (1=mute) |
| | | [2:1] | 合成模式 (00=3xOSC, 01=DX7, 10/11=保留) |
| | | [4:3] | 主音量 (0=最大, 3=最小) |
| 0x04 | R | [0] | WM8731 就绪 (I2C 初始化完成) |
| | | [1] | 保留 |

### 4.2 Track 1 (左声道)

| 偏移 | R/W | 位域 | 说明 |
|------|-----|------|------|
| 0x08 | W | [7:0] | MIDI 音符 (0=释放, 21=A0, 60=C4, 108=C8) |
| 0x0C | W | [1:0] | OSC1 波形 (00=sin, 01=square, 10=saw, 11=tri) |
| | | [3:2] | OSC1 八度偏移 (00=基频, 01=+1, 10=+2, 11=-1) |
| | | [15:8] | OSC1 音量 (0-255) |
| 0x10 | W | [1:0] | OSC2 波形 |
| | | [3:2] | OSC2 八度偏移 |
| | | [7:0] | OSC2 音量 |
| | | [15:8] | OSC2 微调 (detune, -128~+127 cents) |
| 0x14 | W | 同 OSC2 | OSC3 波形/八度/音量/微调 |
| 0x18 | W | [7:0] | DX7: 调制器频率比 (0.5=0, 1=1, 2=2, 3=3, 4=4) |
| | | [15:8] | DX7: 调制指数 (0-127, 0=纯 sine, 127=最强 FM) |
| 0x1C | W | [3:0] | DX7: AR (Attack rate, 0-15) |
| | | [7:4] | DX7: DR (Decay rate, 0-15) |
| 0x20 | W | [3:0] | DX7: SL (Sustain level, 0-15) |
| | | [7:4] | DX7: RR (Release rate, 0-15) |

### 4.3 Track 2 (右声道)

| 偏移 | R/W | 说明 |
|------|-----|------|
| 0x24-0x3C | 同 Track 1 (偏移 +0x1C) | Track 2 的完整寄存器集 |

---

## 5. PS/2 键盘映射

### 5.1 Track 1 — 主键盘区

```
黑键 (上面一排):          白键 (中间一排):
 Q  = C#4    W  = D#4    A  = C4   S  = D4   D  = E4   F  = F4   G  = G4
                    E  = F#4    H  = A4   J  = B4   K  = C5   L  = C#5
                              R  = G#4                              ;  = D5
                    T  = A#4
  Tab  = 八度 -1 (向下)
  CapsLock = 八度 +1 (向上)
```

**扫描码映射 (make code → MIDI note):**

| 按键 | 扫描码 (make) | MIDI 音符 (默认八度 4) |
|------|---------------|------------------------|
| A | 0x1C | 60 (C4) |
| S | 0x1B | 62 (D4) |
| D | 0x23 | 64 (E4) |
| F | 0x2B | 65 (F4) |
| G | 0x34 | 67 (G4) |
| H | 0x33 | 69 (A4) |
| J | 0x2C | 71 (B4) |
| K | 0x35 | 72 (C5) |
| L | 0x3B | 74 (D5) |
| ; | 0x3C | 74 (D5) |
| W | 0x1D | 61 (C#4) |
| E | 0x24 | 66 (F#4) |
| T | 0x2D | 68 (G#4) |
| Y | 0x15 | 70 (A#4) |
| U | 0x2C | (同 K) |
| O | 0x12 | 73 (C#5) |
| P | 0x13 | 75 (D#5) |

### 5.2 Track 2 — 数字小键盘区

```
  Num 7 = C4    Num 8 = D4    Num 9 = E4    Num / = F4
  Num 4 = G4    Num 5 = A4    Num 6 = B4    Num * = C5
  Num 1 = C3    Num 2 = D3    Num 3 = E3    Num - = F3
  Num 0 = G3    Num . = A3    NumEnter = B3  Num + = 八度 +1
  NumLock = 八度切换
```

---

## 6. 两种合成模式的实现细节

### 6.1 3xOSC 模式 (加法合成)

```
每个 Track:
  ┌──────────────────────────────────────────────┐
  │  OSC1: 相位累加器(32-bit) + 波表ROM → vol × │
  │  OSC2: 相位累加器(32-bit) + 波表ROM → vol × │
  │  OSC3: 相位累加器(32-bit) + 波表ROM → vol × │
  └──────────────────┬───────────────────────────┘
                     ↓
            output = OSC1 + OSC2 + OSC3 (饱和加法)
```

**DDS 参数:**
- 相位累加器: 32-bit
- 采样率: 48 kHz
- 频率控制字: TW = (f_note × 2^32) / 48000
- A4 (440Hz): TW = 39,276,827 ≈ 0x0257_EEDB

**波表 ROM (256 entry × 16-bit signed, M9K block RAM):**

| 地址范围 | 波形 | 描述 |
|----------|------|------|
| 0x000-0x0FF | Sine | 正弦波 |
| 0x100-0x1FF | Square | 方波 (0x7FFF / 0x8000) |
| 0x200-0x2FF | Sawtooth | 锯齿波 (-32768→+32767) |
| 0x300-0x3FF | Triangle | 三角波 |

总大小: 1024 × 16 = 16,384 bits = 2 M9K (一个 block RAM)

**八度偏移**: TW × 2^(octave_shift), 硬件左移。

**微调 (detune)**: TW × 2^(cents/1200), 近似为 TW × (1 + cents × 0.000578)。可以用一个小的乘法器或查找表。

### 6.2 DX7 模式 (FM 合成)

```
每个 Track:
  ┌──────────────────────────────────────────────┐
  │  Modulator:                                  │
  │    phase_acc_m → log_sine_LUT → +env_m       │
  │    freq_m = base_freq × ratio               │
  │                    ↓                         │
  │                    modulation (13-bit)         │
  │                    ↓                         │
  │  Carrier:                                    │
  │    phase_acc_c += modulation × index         │
  │    phase_acc_c → log_sine_LUT → +env_c      │
  │    → exp_LUT → signed 16-bit output         │
  └──────────────────────────────────────────────┘
```

**关键: log 域计算, 零乘法器:**
1. `log_sin = log_sine_LUT[theta]` (256×12 ROM)
2. `level = log_sin + envelope` (加法 = 乘法)
3. `output = exp_LUT[level & 0xFF] << (15 - (level >> 8))` (查表 + 移位)

**ROM 资源 (两轨共享):**
- `log_sine_LUT`: 256 × 12-bit = 3,072 bits (~1 M9K)
- `exp_LUT`: 256 × 10-bit = 2,560 bits (~1 M9K)
- 总计: ~2 M9K

**ADSR 包络:**
- ATTACK: env 从当前值递减到 0, 速率由 AR 寄存器控制
- DECAY: env 从 0 递增到 SL 水平, 速率由 DR 寄存器控制
- SUSTAIN: env 保持 (或按 RR 速率递减, 由 EGT 位控制)
- RELEASE: env 从当前值递增到 511 (静音), 速率由 RR 寄存器控制

---

## 7. 资源估算

| 模块 | LEs | M9K | DSP | 说明 |
|------|-----|-----|-----|------|
| WM8731 I2C 控制器 | ~200 | 0 | 0 | I2C FSM + 配置序列 |
| I2S 发送器 | ~100 | 0 | 0 | 移位寄存器 + 分频器 |
| 6× DDS 核心 (3xOSC) | ~300 | 2 | 0 | 32-bit 累加器 + 波表 ROM |
| 4× FM 算子 (DX7) | ~400 | 2 | 0 | log/exp LUT + 相位 + 包络 |
| 模式 MUX + 混音器 | ~100 | 0 | 0 | 多路选择 + 饱和加法 |
| WB 寄存器文件 | ~150 | 0 | 0 | ~16 个寄存器 |
| **合计** | **~1,250** | **~4** | **0** | 占板载: 1.1% LE, 0.9% M9K |

---

## 8. 实现步骤

### Phase 1: WM8731 驱动 (最小可验证)
1. 新增 18.432 MHz PLL 输出到 `clk_rst_gen`
2. 移植 I2C 控制器 (Verilog → VHDL)
3. 移植 I2C 配置序列 (WM8731 初始化)
4. 实现 I2S 发送器 (从寄存器读 16-bit 数据, 串行发送)
5. 上板测试: 播放 440Hz 正弦波测试音

### Phase 2: 3xOSC 基础
6. 实现 DDS 核心 (相位累加器 + 波表 ROM)
7. 实现 6 通道 DDS (3/track) + 混音器
8. WB 寄存器接口
9. C 驱动: 写频率/波形/音量寄存器

### Phase 3: PS/2 键盘演奏
10. C 软件层: 扫描码 → MIDI 音符查找表
11. 八度切换 + 双轨分路
12. `synth` CLI 命令启动合成器模式

### Phase 4: DX7 FM 模式
13. 移植 log_sine_LUT + exp_LUT (SystemVerilog → VHDL 或直接编译)
14. 移植 phase_generator + envelope_generator
15. 4 个独立算子实例 + FM 连接
16. WB 寄存器: ratio, index, AR/DR/SL/RR
17. 软件切换 3xOSC / DX7 模式

### Phase 5: 打磨
18. ADSR 包络调参
19. 音量/混音平衡
20. 音色预设保存/加载

---

## 9. Quartus 工程修改

### QSF 新增文件

```
set_global_assignment -name VERILOG_FILE [file path]synth_engine.sv
```

或移植到 VHDL 后:
```
set_global_assignment -name VHDL_FILE [file path]wm8731_ctrl.vhd
set_global_assignment -name VHDL_FILE [file path]i2s_tx.vhd
set_global_assignment -name VHDL_FILE [file path]dds_core.vhd
set_global_assignment -name VHDL_FILE [file path]fm_operator.vhd
set_global_assignment -name VHDL_FILE [file path]synth_engine.vhd
```

### 引脚分配 (新增)

```
set_location_assignment PIN_E1 -to AUD_XCK
set_location_assignment PIN_F2 -to AUD_BCLK
set_location_assignment PIN_E3 -to AUD_DACLRCK
set_location_assignment PIN_D1 -to AUD_DACDAT
set_location_assignment PIN_C2 -to AUD_ADCLRCK  # 可选
set_location_assignment PIN_D2 -to AUD_ADCDAT    # 可选
set_location_assignment PIN_B7 -to I2C_SCLK
set_location_assignment PIN_A8 -to I2C_SDAT
```

### PLL 修改 (clk_rst_gen)

新增 18.432 MHz 输出 (或 WM8731 可接受的频率):
```
输出 0: 50 MHz  (CPU + Wishbone)
输出 1: 100 MHz (SDRAM)
输出 2: DRAM_CLK (90° 相移)
输出 3: 18.432 MHz (AUD_XCK) ← 新增
```

### wb_intercon 修改

- `s_b` 端口已有地址 0xF0013000 (原 "DDS reserved", now mapped to s13)
- 无需修改地址解码, 只需确认 5-bit 地址宽度

### de2os_top 修改

```vhdl
-- 新增信号
signal synth_wb_adr : std_logic_vector(4 downto 0);
signal synth_wb_dat_i : std_logic_vector(31 downto 0);
signal synth_wb_dat_o : std_logic_vector(31 downto 0);
signal synth_wb_we   : std_logic;
signal synth_wb_stb  : std_logic;
signal synth_wb_ack  : std_logic;

-- 实例化
u_synth : entity work.synth_engine
    port map (
        clk_i       => clk_50,
        rst_n_i     => rst_n,
        wb_adr_i    => synth_wb_adr,
        wb_dat_i    => synth_wb_dat_i,
        wb_dat_o    => synth_wb_dat_o,
        wb_we_i     => synth_wb_we,
        wb_stb_i    => synth_wb_stb,
        wb_ack_o    => synth_wb_ack,
        -- WM8731
        aud_xck     => AUD_XCK,
        aud_bclk    => AUD_BCLK,
        aud_daclrck => AUD_DACLRCK,
        aud_dacdat  => AUD_DACDAT,
        i2c_sclk    => I2C_SCLK,
        i2c_sdat    => I2C_SDAT
    );
```

---

## 10. 软件层

### C 驱动 (`sw/app/de2shell/synth.c`)

```c
#include "neorv32.h"

#define SYNTH_BASE (0xF0013000)

// 全局
#define SYNTH_CTRL   (*(volatile uint32_t*)(SYNTH_BASE + 0x00))
#define SYNTH_STATUS (*(volatile uint32_t*)(SYNTH_BASE + 0x04))

// Track 1 (L)
#define SYNTH_T1_NOTE  (*(volatile uint32_t*)(SYNTH_BASE + 0x08))
#define SYNTH_T1_OSC1  (*(volatile uint32_t*)(SYNTH_BASE + 0x0C))
// ... (同 plan 文档中的完整寄存器表)

// Track 2 (R)
#define SYNTH_T2_NOTE  (*(volatile uint32_t*)(SYNTH_BASE + 0x24))
// ...

// MIDI 音符 → DDS 频率控制字
uint32_t midi_to_tuning_word(uint8_t note) {
    // f = 440 * 2^((note - 69) / 12)
    // TW = f * 2^32 / 48000
    // 简化: 使用预计算的查找表
    extern const uint32_t tuning_table[88]; // A0(21) to C8(108)
    return tuning_table[note - 21];
}

// PS/2 扫描码 → MIDI 音符查找表
const uint8_t key_map_track1[] = { ... };
const uint8_t key_map_track2[] = { ... };
```

### PS/2 按键追踪

使用已有的 `ps2_controller.vhd` + `ps2_decoder.c`:
1. `t_uart_input` 任务轮询 PS/2 MMIO
2. 解码扫描码
3. 查 key_map 表得到 MIDI 音符
4. 写 SYNTH_T1_NOTE / SYNTH_T2_NOTE 寄存器
5. Break code (0xF0) 写 0 释放音符

---

## 11. 不做的事

| 项目 | 原因 |
|------|------|
| 板端 MP3 解码 | 50MHz RV32IMC 算力不够 |
| 复音 (polyphony) | 每轨只支持单音, 降低复杂度 |
| 完整 OPL3 寄存器兼容 | 只需要双轨 2-op FM, 不需要 36 算子 |
| AD/DA 双向 | 只用 DAC 播放, 不录音 |
| MIDI IN/OUT 接口 | PS/2 键盘直接输入, 无需外部 MIDI 设备 |
