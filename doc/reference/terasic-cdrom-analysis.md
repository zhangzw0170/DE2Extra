# DE2-115 官方例程参考手册

> 来源: `DE2-115_v.3.0.6_SystemCD.zip` (Terasic, 2018-07-03)
> 更新: 2026-05-23 — 新增 Nios II vs 纯 HDL 分类

---

## 例程分类

### 纯 Verilog/HDL（可直接翻译为 VHDL）

| # | 目录 | 功能 | 关键文件 |
|---|---|---|---|
| 1 | `DE2_115_Default` | 全外设演示 | VGA/Audio I2C/I2S/LCD/HEX — 17 个 .v 文件 |
| 2 | `DE2_115_PS2_DEMO` | PS/2 鼠标 | `ps2.v` (收发器), `SEG7_LUT.v` |
| 3 | `DE2_115_IR` | 红外遥控 | `IR_RECEIVE_Terasic.v`, `SEG_HEX.v`, `pll1.v` |
| 4 | `DE2_115_TV` | TV 视频输入 | `DE2_115_TV.v` + `v/` 子目录, SDRAM 4 端口 |
| 5 | `DE2_115_i2sound` | **纯硬件 I2S 音频** | `i2c.v`, `keytr.v`, `clock_500.v` (仅 3 文件!) |
| 6 | `DE2_115_golden_top` | 工厂全外设测试顶层 | 参考引脚连接 |

### 基于 Nios II（Qsys SOPC + C 软件，需移植）

| # | 目录 | C 软件内容 | 移植难度 |
|---|---|---|---|
| 7 | `DE2_115_Audio` | WM8731 录制/播放控制 | 中 — 剥 Altera HAL，替换 SPI/I2C 驱动 |
| 8 | `DE2_115_SD_CARD` | SD SPI + **terasic_fat (FAT16/32)** | 高 — 完整的文件系统，深度依赖 HAL |
| 9 | `DE2_115_SD_Card_Audio_Player` | SD 卡 WAV 音乐播放器 | 高 — 叠加 FAT + WAV 解析 |
| 10 | `DE2_115_Synthesizer` | **PS/2 键盘 → MIDI → 波形合成 → 音频输出** | 高 — 多模块联动 |
| 11 | `DE2_115_Web_Server` | TCP/IP + HTTP 服务器 (4 种以太网变体) | 很高 — Nios II LWIP 栈 |
| 12 | `DE2_115_NIOS_HOST_MOUSE_VGA` | 鼠标 + VGA 帧缓冲 + 画图 | 中 — UI 逻辑 |
| 13 | `DE2_115_USB_DEVICE` | USB 设备端 | 很高 — USB 协议栈 |
| 14 | `DE2_115_golden_sopc` | 工厂全 SOPC 系统 | — |

---

## 1. DE2_115_Default — 全外设演示 ⭐⭐⭐

**文件**: `V/` 目录下 17 个 `.v` 文件

| 文件 | 功能 | 可学点 |
|---|---|---|
| `DE2_115_Default.v` | 顶层，所有外设实例化 | 引脚连接方式、时钟分配 |
| `vga_controller.v` | VGA 时序 + 图片 ROM | **VGA 时序参数已验证，和我们的完全一致** |
| `video_sync_generator.v` | HS/VS/blank 生成 | 参数化设计，计数器逻辑清晰 |
| `VGA_Audio_PLL.v` | PLL 生成 VGA 时钟 | 用 PLL 而非 DFF 分频 |
| `AUDIO_DAC.v` | I2S 音频发送 | **I2S 协议参考，直接可翻译成 VHDL** |
| `I2C_Controller.v` | 通用 I2C 主机 | **可直接翻译，用于 WM8731/ADV7180 配置** |
| `I2C_AV_Config.v` | WM8731 初始化参数 | **寄存器值已配好，省去查 datasheet** |
| `LCD_Controller.v` | HD44780 驱动 | 和我们 Exp13 逻辑相同 |
| `LCD_TEST.v` | LCD 测试图案 | 辅助 |
| `SEG7_LUT.v` | 七段管译码 | 和我们 Exp3 相同 |
| `SEG7_LUT_8.v` | 8 位七段管封装 | 省事 |
| `Reset_Delay.v` | 上电复位延迟 | **可能需要，避免 PLL 未锁定时操作** |
| `img_data.v` | 图片 ROM (MegaFunction) | Quartus IP 实例化参考 |
| `img_index.v` | 调色板 ROM | 同上 |

### 对比：VGA 时序参数

| 参数 | Terasic | 我们 (Exp6 → vga_text_terminal.vhd) |
|---|---|---|
| H Total / H Sync / H BP / H Active | 800 / 96 / 48 / 640 | 800 / 96 / 48 / 640 |
| V Total / V Sync / V BP / V Active | 525 / 2 / 32 / 480 | 525 / 2 / 33 / 480 |

**结论**: VGA 时序完全相同（V BP 差 1 行不影响同步）。不需改动。

---

## 2. DE2_115_PS2_DEMO — PS/2 鼠标 ⭐⭐

| 文件 | 功能 |
|---|---|
| `ps2.v` | PS/2 鼠标收发 (双向 tristate, 含 F4 enable 指令) |
| `SEG7_LUT.v` | 七段管译码 |

### 对比：PS/2 实现

| 特性 | Terasic | 我们 (Exp8 → ps2_controller.vhd) |
|---|---|---|
| 协议 | 双向收发 | 单向接收 (只收扫描码) |
| 用途 | 鼠标 (3 字节包, X/Y 位移) | 键盘 (1 字节扫描码) |
| Tristate I/O | `inout` 端口 | `in` 端口 (不需发数据) |
| 奇偶校验 | 无 (只做移位) | 有 (奇校验 + 停止位) |

**结论**: 我们的接收器更严谨（有校验），Terasic 的收发器更完整。键盘场景无需改动。

---

## 3. 音频相关 — 两套方案对比 ⭐⭐⭐

Terasic 提供了**两套独立的音频实现**，复杂度相差很大。

### 方案 A: DE2_115_i2sound（纯硬件, 3 文件）⭐推荐

| 文件 | 功能 |
|---|---|
| `i2c.v` | I2C 主机 (寄存器初始化 WM8731) |
| `keytr.v` | 按键消抖 + 模式切换 (正弦波/静音) |
| `clock_500.v` | 时钟分频 (50MHz → 采样率) |

**极简架构**: I2C 初始化 WM8731 → 内部正弦波 ROM → I2S 直接输出。不需要 Nios II，不需要 CPU，上电就响。

**文件格式**: `.bdf` 原理图 + `.v` Verilog，总共约 200 行代码。

### 方案 B: DE2_115_Default/V/（复杂, 17 文件）

| 文件 | 功能 | 翻译难度 |
|---|---|---|
| `AUDIO_DAC.v` | I2S 发送器 + 多路音频源选通 (Flash/SDRAM/SRAM/正弦波) | 低 — 我们只需要正弦波部分 |
| `I2C_Controller.v` | 通用 I2C 主机 (33 状态 FSM) | 中 — ~200 行 |
| `I2C_AV_Config.v` | WM8731 配置序列 (含视频 ADV7180 寄存器) | 低 — LUT 复制 |

### 推荐: 方案 A (i2sound)

`i2sound` 的极简设计正好匹配我们的需求。我们只需要 CPU 通过寄存器写入采样值，I2S 自动发送。3 个文件翻译成 1 个 `wm8731_ctrl.vhd`（合并 I2C + 初始化 + 简单正弦波 ROM）即可。

### WM8731 配置 (I2C_AV_Config.v 中的寄存器表)

```
Reg 00: 0x001A  — Left Line In (0dB, enable)
Reg 02: 0x001A  — Right Line In
Reg 04: 0x0079  — Left Headphone Out (0dB)
Reg 06: 0x0079  — Right Headphone Out
Reg 08: 0x0012  — Analog Path (DAC select, no sidetone)
Reg 0A: 0x0000  — Digital Path (no filter)
Reg 0C: 0x0062  — Power Down (OSC+OUT+HP on)
Reg 0E: 0x0042  — Digital Format (I2S, 16-bit)
Reg 10: 0x000C  — Sampling Control (48KHz, USB mode off)
Reg 12: 0x0001  — Active Control (activate)
```

这些参数已配好，翻译成 VHDL 数组即可。

---

## 4. SD 卡相关 ⭐⭐⭐

| 目录 | 内容 |
|---|---|
| `DE2_115_SD_CARD/` | SD 卡读写 (SPI 模式) |
| `DE2_115_SD_Card_Audio_Player/` | SD 卡 WAV 播放器 |

这两个都是 Nios II SOPC 系统，硬件部分在 Qsys 中配置，软件用 C 驱动 SD 卡。SD 的 SPI 通信由 Qsys 的 SPI 核处理，不是手写 VHDL——参考资料价值有限。但 **SD Card Music Player** 的 WAV 解析逻辑 (C) 可以直接翻译到我们的 de2shell C 程序。

---

## 5. 音乐合成器 DE2_115_Synthesizer ⭐⭐⭐

这是一个完整的**硬件音乐工作站**，Terrasic CD-ROM 中最炫的 demo。

**硬件**: PS/2 键盘 → Qsys SOPC (Nios II + 多个自定义 VHDL 模块) → WM8731 音频输出 + VGA 乐谱显示

**自定义 VHDL 波形发生器** (`v/` 目录):

| 文件 | 功能 |
|---|---|
| `wave_gen_sin.v` | 正弦波 |
| `wave_gen_square.v` | 方波 |
| `wave_gen_brass.v` | 铜管乐器波形 (谐波叠加) |
| `wave_gen_string.v` | 弦乐波形 |
| `wave_gen_ramp.v` | 锯齿波 |
| `wave_gen_x2.v` | 倍频叠加 |

**VGA 乐谱显示**: `staff.v`, `bar.v` 等用 VGA 绘制五线谱和音符。

**C 软件**: `demo_sound1-4.v` 是 Verilog ROM 文件（预存旋律）。主控逻辑在 Nios II C 程序中，处理键盘→音高映射和音色切换。

### 移植价值

| 可翻译 | 不可翻译 |
|---|---|
| VHDL 波形发生器 (6 种音色) → 直接翻译为 VHDL | Nios II 主控逻辑 → 需用 de2shell C 代替 |
| VGA 乐谱绘制 → 可参考绘制算法 | Qsys 系统互连 → 替换为 wb_intercon |

---

## 6. Nios II C 代码 → RISC-V 移植指南

Terasic 的 8 个 Nios II 例程全部使用 **Altera HAL (Hardware Abstraction Layer)**。移植到 NEORV32 bare-metal 需要替换以下层：

| Altera HAL 函数 | NEORV32 替代 | 难度 |
|---|---|---|
| `alt_printf()` | 已有 `io_puts()` / `vga_puts()` | ✅ 已解决 |
| `IOWR(base, offset, val)` | `*(volatile uint32_t*)(base + offset) = val` | ✅ 直接替换 |
| `IORD(base, offset)` | `*(volatile uint32_t*)(base + offset)` | ✅ 直接替换 |
| `alt_up_sd_card_*()` | 自己写 SD SPI 驱动 | ⚠️ 中 |
| `alt_up_audio_*()` | wm8731_ctrl + i2s_tx (VHDL) | ⚠️ 中 |
| `alt_irq_*()` (中断) | NEORV32 mext_irq + 轮询 | ⚠️ 中 |
| `alt_tick()` (系统时钟) | 系统定时器 (Phase 4 补) | ⚠️ 轻量 |
| `fopen/fread/fwrite` | FAT 文件系统 (petit_fatfs) | ⚠️ 高 |
| `lwip_*()` (TCP/IP) | — | 🔴 很高 |

### 移植流程 (以 SD_CARD 为例)

1. 把 `terasic_sdcard/sd_hal.c` 中的 `IOWR/IORD` 替换为直接内存访问
2. 把 `terasic_fat/FatInternal.c` 中的文件操作替换为 bare-metal 实现
3. 剥离所有 `alt_*` 初始化函数
4. 用 NEORV32 SPI 或 GPIO bit-bang 替代 Altera SPI 核
5. 集成到 de2shell 的 `init/update/input/finish` 框架

---

## 7. 其他参考价值

| 文件 | 可学点 |
|---|---|
| `Reset_Delay.v` | DE2-115 上电后 PLL 需要 ~10ms 锁定，在 PLL 未就绪前不应操作任何外设。我们的 `clk_rst_gen.vhd` 已有 PLL locked 检测，但可能需要在顶层加复位延迟。 |
| `DE2_115_golden_top.v` | Terasic 工厂测试的顶层文件，包含所有外设的默认连接方式。可参考引脚分配和 I/O 标准。 |
| `DE2_115_Web_Server/` | 以太网 TCP/IP + HTTP 的 Nios II C 实现。LWIP 栈参考，但翻译到 bare-metal NEORV32 工作量较大。 |

---

## 8. 后续建议

1. **立即可用**: `Reset_Delay.v` 翻译成 VHDL，增强上电可靠性
2. **短期 (音频)**: `i2sound` 的 3 个 .v 文件 + `I2C_AV_Config.v` 的寄存器 LUT → 合并翻译为 `wm8731_ctrl.vhd`
3. **中期 (SD 卡)**: 在 de2shell 中加入 SD 卡 SPI 驱动 (C)，移植 `terasic_fat`
4. **长期 (合成器)**: 6 种波形发生器 VHDL 可直接翻译，主控用 de2shell C 重写
5. **长期 (以太网)**: 需要 LWIP 移植，工作量大，优先级最低
6. **不需改动**: VGA 时序、PS/2 接收、七段管、LCD — 我们的实现已经正确
