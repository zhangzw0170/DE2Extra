# DE2Extra — FPGA 全外设操作系统级项目

> NEORV32 (RISC-V) + FreeRTOS + LVGL，目标：让 DE2-115 变成一台完整的计算机

## 硬件平台

**主平台**: Terasic DE2-115 (Cyclone IV E EP4CE115F29C7)
**移植目标**: 达芬奇 A7Pro

- **FPGA**: 114,480 LEs, 266 hardware multipliers, 4 PLLs
- **Memory**: 128MB SDRAM, 2MB SRAM, 8MB Flash, 32Kbit EEPROM, SD card
- **Display**: 16x2 LCD, 8x 7-segment, 27 LEDs (9G + 18R), VGA (24-bit)
- **Comms**: 2x Gigabit Ethernet, USB 2.0 OTG, RS-232, PS/2 x2, IR
- **Audio**: WM8731 24-bit CODEC (line-in/out, mic-in)
- **Video**: VGA out (24-bit DAC), TV in (ADV7180 NTSC/PAL/SECAM)
- **Clock**: 3x 50MHz, SMA in/out
- **Input**: 4 push-buttons, 18 slide switches
- **Expansion**: 40-pin GPIO, 172-pin HSMC, 7-pin EX_IO

Full pin tables: [DE2-115_Resource_Summary.md](DE2-115_Resource_Summary.md)

## 技术路线

```
┌──────────────────────────────────────────────────┐
│              LVGL 720p GUI                        │
│         按钮、图表、动画、虚拟键盘                  │
├──────────────────────────────────────────────────┤
│              FreeRTOS                             │
│     任务调度、定时器、中断管理、IPC                 │
├──────────────────────────────────────────────────┤
│     NEORV32 RISC-V 软核 (~2300 LUTs)             │
│     rv32imc_Zicsr, ~50 DMIPS @50MHz              │
├──────────────────────────────────────────────────┤
│  自定义 VHDL 外设控制器 (平台无关寄存器接口)        │
│  VGA | PS/2 | Audio | Ethernet | UART | SD | ...  │
├──────────────────────────────────────────────────┤
│     FPGA 硬件 (DE2-115 / 达芬奇 A7Pro)            │
└──────────────────────────────────────────────────┘
```

### CPU: NEORV32 (RISC-V)

开源 RISC-V 处理器，纯 VHDL 实现，作为 submodule 引入。

- 源码: [neorv32/](neorv32/) (submodule → github.com/stnolting/neorv32)
- ISA: RV32IMC + Zicsr + Zicntr + 自定义扩展
- Cyclone IV 实测: ~2300 LUTs, 128 MHz fmax, 95 CoreMark
- 自带: UART, SPI, I2C, GPIO, PWM, WDT, TRNG, JTAG debugger
- 外部总线: Wishbone (附赠 Avalon / AXI4 桥接)
- 工具链: RISC-V GCC (主流，永久维护)
- 许可: MIT

### 外设设计规范

所有自定义外设只暴露通用寄存器接口，不绑定任何总线：

```vhdl
entity xxx_controller is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        -- 通用寄存器接口
        cs      : in  std_logic;
        wr_en   : in  std_logic;
        rd_en   : in  std_logic;
        addr    : in  std_logic_vector(3 downto 0);
        wr_data : in  std_logic_vector(31 downto 0);
        rd_data : out std_logic_vector(31 downto 0);
        irq     : out std_logic;
        -- 硬件引脚
        ...
    );
end entity;
```

总线适配层单独写，换 CPU / 换板子只需改适配层，外设核心不动。

### 外设模块规划

| 模块           | 说明                           | 优先级 |
| -------------- | ------------------------------ | ------ |
| vga_controller | 720p 帧缓冲 + VGA 时序         | P0     |
| sdram_ctrl     | SDRAM 控制器 (帧缓冲+CPU 内存) | P0     |
| ps2_keyboard   | PS/2 键盘                      | P0     |
| ps2_mouse      | PS/2 鼠标                      | P1     |
| uart           | RS-232 调试串口                | P0     |
| timer_module   | 系统定时器 (FreeRTOS 心跳)     | P0     |
| interrupt_ctrl | 中断控制器                     | P0     |
| spi_sd_card    | SD 卡 (存资源)                 | P1     |
| i2c_master     | I2C (配置音频/TV芯片)          | P1     |
| audio_i2s      | I2S 音频输出 (WM8731)          | P2     |
| lcd_controller | HD44780 LCD                    | P2     |
| irda_receiver  | 红外 NEC 解码                  | P2     |
| eth_mac        | 以太网 MAC                     | P3     |
| usb_ctrl       | USB OTG (ISP1362)              | P3     |

## Conventions

- HDL language: **VHDL only** (VHDL-2008 where supported)
- File extension: `.vhd`
- Entity/architecture in one file, file name matches entity name
- Active-low signals suffixed `_N` (e.g. `CS_N`, `RESET_N`)
- Clock signals prefixed `clk_` (e.g. `clk_50m`, `clk_vga`)
- Reset signals prefixed `rst_`, active-high unless suffixed `_N`
- One clock domain per entity; cross-domain via synchronizer components
- Top-level entity: `de2_115_top`

## Directory Layout

```
DE2Extra/
├── README.md                       # this file
├── DE2-115_Resource_Summary.md     # full pin tables & specs
├── neorv32/                        # NEORV32 RISC-V CPU (git submodule)
├── src/
│   ├── rtl/                        # synthesizable VHDL
│   │   ├── de2_115_top.vhd         # top-level entity
│   │   ├── periph/                 # peripheral controllers
│   │   │   ├── vga_controller.vhd
│   │   │   ├── sdram_ctrl.vhd
│   │   │   ├── ps2_keyboard.vhd
│   │   │   └── ...
│   │   ├── bus/                    # bus adapters (Wishbone ↔ register IF)
│   │   └── glue/                   # clock/reset/glue logic
│   ├── sim/                        # testbenches
│   │   └── tb_*.vhd
│   └── ip/                         # Quartus IP cores
├── sw/                             # software (RISC-V GCC)
│   ├── freertos/                   # FreeRTOS port
│   ├── lvgl/                       # LVGL port
│   ├── drivers/                    # peripheral drivers (C)
│   └── app/                        # application code
├── par/                            # Quartus project files
├── constraints/                    # pin assignments, timing (.sdc, .tcl)
└── doc/                            # design notes, block diagrams
```

## Toolchain

| Tool                       | Purpose                   |
| -------------------------- | ------------------------- |
| Quartus Prime 23.1std Lite | FPGA 综合, 布局布线, 编程 |
| QuestaSim                  | VHDL 仿真                 |
| RISC-V GCC (prebuilt)      | 软件交叉编译              |
| OpenOCD + GDB              | JTAG 调试                 |
| FreeRTOS                   | 实时操作系统              |
| LVGL                       | 图形界面库                |

Target device: `EP4CE115F29C7`

## Build

### 首次打开项目 (必须)

NEORV32 使用 VHDL-2008 语法 (`std_ulogic`、record 类型等)，Quartus 默认是 VHDL-93，必须手动切换：

1. 打开 `par/de2extra.qpf`
2. **Assignments → Settings → Compiler Settings → VHDL Input**
3. 改为 **VHDL 2008**
4. 点 OK

这一步只做一次，之后 Quartus 会记住设置。

### 编译

```
# Hardware (Quartus)
quartus_sh --flow compile de2extra

# Software (RISC-V GCC)
cd sw/app && make

# Flash
quartus_pgm -m jtag -o "p;output_files/de2extra.sof"
```

## Portability

外设控制器设计为平台无关，移植到其他 FPGA 板只需：

1. 替换顶层引脚约束 (`constraints/`)
2. 替换 PLL 配置 (不同板子时钟频率可能不同)
3. 外设模块 VHDL 代码 **零修改**

已知移植目标：达芬奇 A7Pro
