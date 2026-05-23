# DE2-115 官方例程参考手册

> 来源: `DE2-115_v.3.0.6_SystemCD.zip` (Terasic, 2018-07-03)
> 全部为 Verilog，供架构和参数参考。

---

## 例程清单

| # | 目录 | 功能 | 语言 | 对我们有用 |
|---|---|---|---|---|
| 1 | `DE2_115_Default` | 全外设演示 (VGA+Audio+LCD+HEX+LED) | Verilog | ⭐⭐⭐ |
| 2 | `DE2_115_PS2_DEMO` | PS/2 鼠标控制 | Verilog | ⭐⭐ |
| 3 | `DE2_115_IR` | 红外遥控接收 | Verilog | ⭐ |
| 4 | `DE2_115_TV` | TV 视频输入 (ADV7180) | Verilog | ⭐⭐⭐ |
| 5 | `DE2_115_Audio` | 音频录制与播放 | Verilog + Nios II | ⭐⭐⭐ |
| 6 | `DE2_115_SD_CARD` | SD 卡读写 | Verilog + Nios II | ⭐⭐⭐ |
| 7 | `DE2_115_SD_Card_Audio_Player` | SD 卡音频播放器 | Verilog + Nios II | ⭐⭐⭐ |
| 8 | `DE2_115_Synthesizer` | 音乐合成器 | Verilog + Nios II | ⭐⭐ |
| 9 | `DE2_115_Web_Server` | 以太网 Web 服务器 | Verilog + Nios II | ⭐⭐ |
| 10 | `DE2_115_NIOS_HOST_MOUSE_VGA` | Nios II VGA 鼠标演示 | SOPC + C | ⭐ |
| 11 | `DE2_115_USB_DEVICE` | USB 设备 | Verilog + Nios II | ⭐ |
| 12 | `DE2_115_i2sound` | I2S 音频 | Verilog | ⭐⭐⭐ |
| 13 | `DE2_115_golden_top` | 金板顶层 | Verilog | ⭐⭐⭐ |
| 14 | `DE2_115_golden_sopc` | 金板 SOPC 系统 | Qsys | ⭐ |

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

## 3. 音频相关 (AUDIO_DAC / I2C_Controller / i2sound) ⭐⭐⭐

这是对我们最有价值的部分——音频硬件目前完全空白。

| 文件 | 来源 | 功能 | 翻译难度 |
|---|---|---|---|
| `AUDIO_DAC.v` | Default/V/ | I2S 发送器 (16-bit, 双声道) | 低 — ~150 行 VHDL |
| `I2C_Controller.v` | Default/V/ | I2C 主机 (100KHz, 单字节读写) | 中 — ~200 行 VHDL |
| `I2C_AV_Config.v` | Default/V/ | WM8731 寄存器配置表 (11 个寄存器) | 低 — 直接翻译数组 |

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

## 5. 其他参考价值

| 文件 | 可学点 |
|---|---|
| `Reset_Delay.v` | DE2-115 上电后 PLL 需要 ~10ms 锁定，在 PLL 未就绪前不应操作任何外设。我们的 `clk_rst_gen.vhd` 已有 PLL locked 检测，但可能需要在顶层加复位延迟。 |
| `DE2_115_golden_top.v` | Terasic 工厂测试的顶层文件，包含所有外设的默认连接方式。可参考引脚分配和 I/O 标准。 |
| `DE2_115_Web_Server/` | 以太网 TCP/IP + HTTP 的 Nios II C 实现。LWIP 栈参考，但翻译到 bare-metal NEORV32 工作量较大。 |

---

## 后续建议

1. **立即可用**: `Reset_Delay.v` 翻译成 VHDL，增强上电可靠性
2. **短期 (音频)**: `I2C_Controller` + `AUDIO_DAC` + `I2C_AV_Config` 翻译 → `src/rtl/periph/wm8731_ctrl.vhd`
3. **中期 (SD 卡)**: 在 de2shell 中加入 SD 卡 SPI 驱动 (C)，参考 Nios II 版本
4. **长期 (以太网)**: 需要 LWIP 移植，工作量大，优先级最低
5. **不需改动**: VGA 时序、PS/2 接收、七段管、LCD — 我们的实现已经正确
