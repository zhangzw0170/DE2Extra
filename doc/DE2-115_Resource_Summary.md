# DE2-115 FPGA 开发板完整资源手册

> 基于引脚表 + 官方规格书整理，Terasic DE2-115 (Cyclone IV E EP4CE115F29C7)

---

## 1. FPGA 核心参数

| 参数 | 数值 |
|------|------|
| 芯片 | Altera Cyclone IV E EP4CE115F29C7 |
| 逻辑单元 (LEs) | 114,480 |
| M9K 存储块 | 432 |
| 嵌入式存储器 | 3,888 Kbits (486 KB) |
| 嵌入式 18×18 乘法器 | 266 |
| 通用 PLL | 4 个 |
| 用户 I/O | 528 |
| 封装 | F29 (780-pin FBGA) |

## 2. 配置与调试

| 资源 | 说明 |
|------|------|
| 配置器件 | EPCS64 (64Mbit 串行 Flash) |
| 编程方式 | JTAG / Active Serial (AS) |
| 调试接口 | 板载 USB-Blaster，支持 JTAG 和 AS 模式 |

## 3. 时钟资源

| 信号名 | 引脚 | 频率 | 说明 |
|--------|------|------|------|
| CLOCK_50 | PIN_Y2 | 50 MHz | 主时钟 |
| CLOCK2_50 | PIN_AG14 | 50 MHz | 辅助时钟 2 |
| CLOCK3_50 | PIN_AG15 | 50 MHz | 辅助时钟 3 |
| SMA_CLKIN | PIN_AH14 | 外部输入 | SMA 外部时钟输入 |
| SMA_CLKOUT | PIN_AE23 | 外部输出 | SMA 外部时钟输出 |

- 三个 50MHz 振荡器通过时钟缓冲器低抖动分配到 FPGA
- 所有时钟输入都连接到 PLL 输入引脚
- SMA 连接器用于外部时钟输入/输出

## 4. 用户输入

### 4.1 按键 KEY (4个)

| 信号名 | 方向 | 引脚 | Bank |
|--------|------|------|------|
| KEY[0] | Input | PIN_M23 | 6 |
| KEY[1] | Input | PIN_M21 | 6 |
| KEY[2] | Input | PIN_N21 | 6 |
| KEY[3] | Input | PIN_R24 | 5 |

### 4.2 拨码开关 SW (18个)

| 信号名 | 方向 | 引脚 | Bank |
|--------|------|------|------|
| SW[0] | Input | PIN_AB28 | 5 |
| SW[1] | Input | PIN_AC28 | 5 |
| SW[2] | Input | PIN_AC27 | 5 |
| SW[3] | Input | PIN_AD27 | 5 |
| SW[4] | Input | PIN_AB27 | 5 |
| SW[5] | Input | PIN_AC26 | 5 |
| SW[6] | Input | PIN_AD26 | 5 |
| SW[7] | Input | PIN_AB26 | 5 |
| SW[8] | Input | PIN_AC25 | 5 |
| SW[9] | Input | PIN_AB25 | 5 |
| SW[10] | Input | PIN_AC24 | 5 |
| SW[11] | Input | PIN_AB24 | 5 |
| SW[12] | Input | PIN_AB23 | 5 |
| SW[13] | Input | PIN_AA24 | 5 |
| SW[14] | Input | PIN_AA23 | 5 |
| SW[15] | Input | PIN_AA22 | 5 |
| SW[16] | Input | PIN_Y24 | 5 |
| SW[17] | Input | PIN_Y23 | 5 |

## 5. 用户输出显示

### 5.1 绿色 LED LEDG (9个)

| 信号名 | 方向 | 引脚 | Bank |
|--------|------|------|------|
| LEDG[0] | Output | PIN_E21 | 7 |
| LEDG[1] | Output | PIN_E22 | 7 |
| LEDG[2] | Output | PIN_E25 | 7 |
| LEDG[3] | Output | PIN_E24 | 7 |
| LEDG[4] | Output | PIN_H21 | 7 |
| LEDG[5] | Output | PIN_G20 | 7 |
| LEDG[6] | Output | PIN_G22 | 7 |
| LEDG[7] | Output | PIN_G21 | 7 |
| LEDG[8] | Output | PIN_F17 | 7 |

### 5.2 红色 LED LEDR (18个)

| 信号名 | 方向 | 引脚 | Bank |
|--------|------|------|------|
| LEDR[0] | Output | PIN_G19 | 7 |
| LEDR[1] | Output | PIN_F19 | 7 |
| LEDR[2] | Output | PIN_E19 | 7 |
| LEDR[3] | Output | PIN_F21 | 7 |
| LEDR[4] | Output | PIN_F18 | 7 |
| LEDR[5] | Output | PIN_E18 | 7 |
| LEDR[6] | Output | PIN_J19 | 7 |
| LEDR[7] | Output | PIN_H19 | 7 |
| LEDR[8] | Output | PIN_J17 | 7 |
| LEDR[9] | Output | PIN_G17 | 7 |
| LEDR[10] | Output | PIN_J15 | 7 |
| LEDR[11] | Output | PIN_H16 | 7 |
| LEDR[12] | Output | PIN_J16 | 7 |
| LEDR[13] | Output | PIN_H17 | 7 |
| LEDR[14] | Output | PIN_F15 | 7 |
| LEDR[15] | Output | PIN_G15 | 7 |
| LEDR[16] | Output | PIN_G16 | 7 |
| LEDR[17] | Output | PIN_H15 | 7 |

### 5.3 七段数码管 HEX (8个)

每个数码管 7 段 (a~g 对应 [6]~[0])，共阴极接法，低电平点亮。

| 数码管 | 段 | 引脚 | Bank |
|--------|----|------|------|
| HEX0 | [6] | PIN_H22 | 6 |
| HEX0 | [5] | PIN_J22 | 6 |
| HEX0 | [4] | PIN_L25 | 6 |
| HEX0 | [3] | PIN_L26 | 6 |
| HEX0 | [2] | PIN_E17 | 7 |
| HEX0 | [1] | PIN_F22 | 7 |
| HEX0 | [0] | PIN_G18 | 7 |
| HEX1 | [6] | PIN_U24 | 5 |
| HEX1 | [5] | PIN_U23 | 5 |
| HEX1 | [4] | PIN_W25 | 5 |
| HEX1 | [3] | PIN_W22 | 5 |
| HEX1 | [2] | PIN_W21 | 5 |
| HEX1 | [1] | PIN_Y22 | 5 |
| HEX1 | [0] | PIN_M24 | 6 |
| HEX2 | [6] | PIN_W28 | 5 |
| HEX2 | [5] | PIN_W27 | 5 |
| HEX2 | [4] | PIN_Y26 | 5 |
| HEX2 | [3] | PIN_W26 | 5 |
| HEX2 | [2] | PIN_Y25 | 5 |
| HEX2 | [1] | PIN_AA26 | 5 |
| HEX2 | [0] | PIN_AA25 | 5 |
| HEX3 | [6] | PIN_Y19 | 4 |
| HEX3 | [5] | PIN_AF23 | 4 |
| HEX3 | [4] | PIN_AD24 | 4 |
| HEX3 | [3] | PIN_AA21 | 4 |
| HEX3 | [2] | PIN_AB20 | 4 |
| HEX3 | [1] | PIN_U21 | 5 |
| HEX3 | [0] | PIN_V21 | 5 |
| HEX4 | [6] | PIN_AE18 | 4 |
| HEX4 | [5] | PIN_AF19 | 4 |
| HEX4 | [4] | PIN_AE19 | 4 |
| HEX4 | [3] | PIN_AH21 | 4 |
| HEX4 | [2] | PIN_AG21 | 4 |
| HEX4 | [1] | PIN_AA19 | 4 |
| HEX4 | [0] | PIN_AB19 | 4 |
| HEX5 | [6] | PIN_AH18 | 4 |
| HEX5 | [5] | PIN_AF18 | 4 |
| HEX5 | [4] | PIN_AG19 | 4 |
| HEX5 | [3] | PIN_AH19 | 4 |
| HEX5 | [2] | PIN_AB18 | 4 |
| HEX5 | [1] | PIN_AC18 | 4 |
| HEX5 | [0] | PIN_AD18 | 4 |
| HEX6 | [6] | PIN_AC17 | 4 |
| HEX6 | [5] | PIN_AA15 | 4 |
| HEX6 | [4] | PIN_AB15 | 4 |
| HEX6 | [3] | PIN_AB17 | 4 |
| HEX6 | [2] | PIN_AA16 | 4 |
| HEX6 | [1] | PIN_AB16 | 4 |
| HEX6 | [0] | PIN_AA17 | 4 |
| HEX7 | [6] | PIN_AA14 | 3 |
| HEX7 | [5] | PIN_AG18 | 4 |
| HEX7 | [4] | PIN_AF17 | 4 |
| HEX7 | [3] | PIN_AH17 | 4 |
| HEX7 | [2] | PIN_AG17 | 4 |
| HEX7 | [1] | PIN_AE17 | 4 |
| HEX7 | [0] | PIN_AD17 | 4 |

### 5.4 LCD 液晶模块 (16x2 字符 LCD)

板载 16 列 × 2 行字符型 LCD 模块，采用 8-bit 并行接口。

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| LCD_DATA[0] | Bidir | PIN_L3 | 数据线 D0 |
| LCD_DATA[1] | Bidir | PIN_L1 | 数据线 D1 |
| LCD_DATA[2] | Bidir | PIN_L2 | 数据线 D2 |
| LCD_DATA[3] | Bidir | PIN_K7 | 数据线 D3 |
| LCD_DATA[4] | Bidir | PIN_K1 | 数据线 D4 |
| LCD_DATA[5] | Bidir | PIN_K2 | 数据线 D5 |
| LCD_DATA[6] | Bidir | PIN_M3 | 数据线 D6 |
| LCD_DATA[7] | Bidir | PIN_M5 | 数据线 D7 |
| LCD_RS | Output | PIN_M2 | 寄存器选择 (0=命令, 1=数据) |
| LCD_RW | Output | PIN_M1 | 读/写 (0=写, 1=读) |
| LCD_EN | Output | PIN_L4 | 使能信号 |
| LCD_ON | Output | PIN_L5 | LCD 电源开关 |
| LCD_BLON | Output | PIN_L6 | 背光开关 |

## 6. 存储器

### 6.1 SDRAM (128MB, 32M×32bit)

使用两片 64MB SDRAM 组成 32-bit 位宽。

| 信号 | 方向 | 引脚 | 说明 |
|------|------|------|------|
| DRAM_ADDR[12:0] | Output | 见引脚表 | 地址线 |
| DRAM_BA[1:0] | Output | PIN_R4, PIN_U7 | Bank 选择 |
| DRAM_CAS_N | Output | PIN_V7 | 列地址选通 |
| DRAM_CKE | Output | PIN_AA6 | 时钟使能 |
| DRAM_CLK | Output | PIN_AE5 | 时钟 |
| DRAM_CS_N | Output | PIN_T4 | 片选 |
| DRAM_DQ[31:0] | Bidir | 见引脚表 | 32-bit 数据线 |
| DRAM_DQM[3:0] | Output | 见引脚表 | 数据掩码 |
| DRAM_RAS_N | Output | PIN_U6 | 行地址选通 |
| DRAM_WE_N | Output | PIN_V6 | 写使能 |

### 6.2 SRAM (2MB, 1M×16bit)

| 信号 | 方向 | 引脚 | 说明 |
|------|------|------|------|
| SRAM_ADDR[19:0] | Output | 见引脚表 | 20-bit 地址线 |
| SRAM_DQ[15:0] | Bidir | 见引脚表 | 16-bit 数据线 |
| SRAM_CE_N | Output | PIN_AF8 | 片选 |
| SRAM_OE_N | Output | PIN_AD5 | 输出使能 |
| SRAM_WE_N | Output | PIN_AE8 | 写使能 |
| SRAM_UB_N | Output | PIN_AC4 | 高字节掩码 |
| SRAM_LB_N | Output | PIN_AD4 | 低字节掩码 |

### 6.3 Flash (8MB, 4M×16bit, 8-bit 模式)

| 信号 | 方向 | 引脚 | 说明 |
|------|------|------|------|
| FL_ADDR[22:0] | Output | 见引脚表 | 23-bit 地址线 |
| FL_DQ[7:0] | Bidir | 见引脚表 | 8-bit 数据线 |
| FL_CE_N | Output | PIN_AG7 | 片选 |
| FL_OE_N | Output | PIN_AG8 | 输出使能 |
| FL_WE_N | Output | PIN_AC10 | 写使能 |
| FL_RST_N | Output | PIN_AE11 | 复位 |
| FL_WP_N | Output | PIN_AE12 | 写保护 |
| FL_RY | Input | PIN_Y1 | Ready/Busy |

### 6.4 EEPROM (32Kbit)

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| EEP_I2C_SCLK | Output | PIN_D14 | I2C 时钟 |
| EEP_I2C_SDAT | Bidir | PIN_E14 | I2C 数据 |

### 6.5 SD 卡槽

支持 SPI 模式和 4-bit SD 模式。

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| SD_CLK | Output | PIN_AE13 | 时钟 |
| SD_CMD | Bidir | PIN_AD14 | 命令/响应 |
| SD_DAT[0] | Bidir | PIN_AE14 | 数据线 0 |
| SD_DAT[1] | Bidir | PIN_AF13 | 数据线 1 |
| SD_DAT[2] | Bidir | PIN_AB14 | 数据线 2 |
| SD_DAT[3] | Bidir | PIN_AC14 | 数据线 3 / CS |
| SD_WP_N | Input | PIN_AF14 | 写保护 |

## 7. 通信接口

### 7.1 千兆以太网 (×2 路)

两路独立的 10/100/1000 Mbps 以太网，PHY 芯片为 Marvell 88E1111。

**ENET0 (第一路, 23 pins):**

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| ENET0_GTX_CLK | Output | PIN_A17 | GTX 时钟 |
| ENET0_TX_DATA[3:0] | Output | 见引脚表 | 发送数据 |
| ENET0_TX_EN | Output | PIN_A18 | 发送使能 |
| ENET0_TX_ER | Output | PIN_B18 | 发送错误 |
| ENET0_TX_CLK | Input | PIN_B17 | 发送时钟 |
| ENET0_RX_DATA[3:0] | Input | 见引脚表 | 接收数据 |
| ENET0_RX_DV | Input | PIN_C17 | 接收数据有效 |
| ENET0_RX_ER | Input | PIN_D18 | 接收错误 |
| ENET0_RX_CLK | Input | PIN_A15 | 接收时钟 |
| ENET0_RX_COL | Input | PIN_E15 | 冲突检测 |
| ENET0_RX_CRS | Input | PIN_D15 | 载波侦听 |
| ENET0_MDC | Output | PIN_C20 | MDIO 时钟 |
| ENET0_MDIO | Bidir | PIN_B21 | MDIO 数据 |
| ENET0_INT_N | Input | PIN_A21 | 中断 |
| ENET0_RST_N | Output | PIN_C19 | 复位 |
| ENET0_LINK100 | Input | PIN_C14 | 100M 链路指示 |

**ENET1 (第二路, 21 pins):** 结构同 ENET0，引脚映射见引脚表。

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| ENETCLK_25 | Input | PIN_A14 | 25MHz 以太网参考时钟 |

### 7.2 USB OTG (USB 2.0 Host/Device)

控制器芯片：ISP1362，支持 Full-Speed 和 Low-Speed。

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| OTG_DATA[15:0] | Bidir | 见引脚表 | 16-bit 数据总线 |
| OTG_ADDR[1:0] | Output | PIN_H7, PIN_C3 | 地址线 |
| OTG_CS_N | Output | PIN_A3 | 片选 |
| OTG_RD_N | Output | PIN_B3 | 读使能 |
| OTG_WR_N | Output | PIN_A4 | 写使能 |
| OTG_RST_N | Output | PIN_C5 | 复位 |
| OTG_INT[1:0] | Input | PIN_A6, PIN_D5 | 中断 |
| OTG_DREQ[1:0] | Input | PIN_J1, PIN_B4 | DMA 请求 |
| OTG_DACK_N[1:0] | Output | PIN_C4, PIN_D4 | DMA 应答 |
| OTG_FSPEED | Bidir | PIN_C6 | Full-Speed 检测 |
| OTG_LSPEED | Bidir | PIN_B6 | Low-Speed 检测 |

- 提供 USB Type A (Host) 和 USB Type B (Device) 接口

### 7.3 UART (RS-232)

带硬件流控的 RS-232 串口，DB-9 连接器。

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| UART_TXD | Output | PIN_G9 | 发送数据 |
| UART_RXD | Input | PIN_G12 | 接收数据 |
| UART_RTS | Input | PIN_J13 | 请求发送 |
| UART_CTS | Output | PIN_G14 | 清除发送 |

### 7.4 PS/2 (鼠标/键盘, 双接口)

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| PS2_CLK | Bidir | PIN_G6 | PS/2 时钟 (键盘) |
| PS2_DAT | Bidir | PIN_H5 | PS/2 数据 (键盘) |
| PS2_CLK2 | Bidir | PIN_G5 | PS/2 时钟 (鼠标) |
| PS2_DAT2 | Bidir | PIN_F5 | PS/2 数据 (鼠标) |

### 7.5 I2C 总线

与 WM8731 音频芯片和 ADV7180 TV 解码器共享。

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| I2C_SCLK | Output | PIN_B7 | I2C 时钟 |
| I2C_SDAT | Bidir | PIN_A8 | I2C 数据 |

### 7.6 红外遥控接收器 (IR Receiver)

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| IRDA_RXD | Input | PIN_Y15 | 红外接收数据 |

> 注意：IRDA_RXD 在引脚表中被归入 I2C 分类，但实际是独立的红外接收模块。

## 8. 音频

### 音频编解码器 WM8731 (24-bit CODEC)

提供 Line-in、Line-out、Microphone-in 三个 3.5mm 音频接口。

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| AUD_XCK | Output | PIN_E1 | 音频主时钟 |
| AUD_BCLK | Bidir | PIN_F2 | 位时钟 (I2S) |
| AUD_ADCLRCK | Bidir | PIN_C2 | ADC 左右声道时钟 |
| AUD_DACLRCK | Bidir | PIN_E3 | DAC 左右声道时钟 |
| AUD_ADCDAT | Input | PIN_D2 | ADC 数据输入 |
| AUD_DACDAT | Output | PIN_D1 | DAC 数据输出 |

- WM8731 通过 I2C 总线配置 (I2C_SCLK / I2C_SDAT)
- 支持 24-bit CD 音质采样
- 采样率最高 96kHz

## 9. 视频

### 9.1 VGA 输出 (8-bit 高速三通道 DAC)

每个颜色通道 8-bit (R[7:0], G[7:0], B[7:0])，共 24-bit 真彩色。

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| VGA_R[7:0] | Output | 见引脚表 | 红色通道 |
| VGA_G[7:0] | Output | 见引脚表 | 绿色通道 |
| VGA_B[7:0] | Output | 见引脚表 | 蓝色通道 |
| VGA_HS | Output | PIN_G13 | 行同步 |
| VGA_VS | Output | PIN_C13 | 场同步 |
| VGA_CLK | Output | PIN_A12 | 像素时钟 |
| VGA_BLANK_N | Output | PIN_F11 | 消隐信号 |
| VGA_SYNC_N | Output | PIN_C10 | 同步信号 |

### 9.2 TV 视频输入 (NTSC/PAL/SECAM 解码器)

解码器芯片：ADV7180，自动检测 NTSC/PAL/SECAM 制式。

| 信号名 | 方向 | 引脚 | 说明 |
|--------|------|------|------|
| TD_CLK27 | Input | PIN_B14 | 27MHz 时钟 |
| TD_DATA[7:0] | Input | 见引脚表 | 8-bit ITU-R BT.656 视频数据 |
| TD_HS | Input | PIN_E5 | 行同步 |
| TD_VS | Input | PIN_E4 | 场同步 |
| TD_RESET_N | Output | PIN_G7 | 复位 |

- ADV7180 通过 I2C 总线配置 (与音频芯片共享)
- 输出标准 ITU-R BT.656 格式

## 10. 扩展接口

### 10.1 GPIO 扩展 (40-pin 排针, 36 个 FPGA I/O)

提供 +5V (VCC5)、+3.3V (VCC3P3) 和两个 GND。支持 3.3V/2.5V/1.8V/1.5V I/O 标准。

| 信号名 | 方向 | 引脚 |
|--------|------|------|
| GPIO[0] | Bidir | PIN_AB22 |
| GPIO[1] | Bidir | PIN_AC15 |
| GPIO[2] | Bidir | PIN_AB21 |
| GPIO[3] | Bidir | PIN_Y17 |
| GPIO[4] | Bidir | PIN_AC21 |
| GPIO[5] | Bidir | PIN_Y16 |
| GPIO[6] | Bidir | PIN_AD21 |
| GPIO[7] | Bidir | PIN_AE16 |
| GPIO[8] | Bidir | PIN_AD15 |
| GPIO[9] | Bidir | PIN_AE15 |
| GPIO[10] | Bidir | PIN_AC19 |
| GPIO[11] | Bidir | PIN_AF16 |
| GPIO[12] | Bidir | PIN_AD19 |
| GPIO[13] | Bidir | PIN_AF15 |
| GPIO[14] | Bidir | PIN_AF24 |
| GPIO[15] | Bidir | PIN_AE21 |
| GPIO[16] | Bidir | PIN_AF25 |
| GPIO[17] | Bidir | PIN_AC22 |
| GPIO[18] | Bidir | PIN_AE22 |
| GPIO[19] | Bidir | PIN_AF21 |
| GPIO[20] | Bidir | PIN_AF22 |
| GPIO[21] | Bidir | PIN_AD22 |
| GPIO[22] | Bidir | PIN_AG25 |
| GPIO[23] | Bidir | PIN_AD25 |
| GPIO[24] | Bidir | PIN_AH25 |
| GPIO[25] | Bidir | PIN_AE25 |
| GPIO[26] | Bidir | PIN_AG22 |
| GPIO[27] | Bidir | PIN_AE24 |
| GPIO[28] | Bidir | PIN_AH22 |
| GPIO[29] | Bidir | PIN_AF26 |
| GPIO[30] | Bidir | PIN_AE20 |
| GPIO[31] | Bidir | PIN_AG23 |
| GPIO[32] | Bidir | PIN_AF20 |
| GPIO[33] | Bidir | PIN_AH26 |
| GPIO[34] | Bidir | PIN_AH23 |
| GPIO[35] | Bidir | PIN_AG26 |

### 10.2 HSMC 高速夹层卡连接器 (172-pin)

82 个 FPGA 引脚直接连接，支持：
- JTAG
- 时钟输入/输出
- 高速 LVDS 差分信号
- 单端信号
- 可配置 I/O 标准 (3.3V/2.5V/1.8V/1.5V)

详细引脚映射见引脚表中 HSMC 分类（82 pins，含 17 对差分 TX、17 对差分 RX、4 个单端 D 信号、时钟等）。

### 10.3 扩展 I/O EX (7个)

| 信号名 | 方向 | 引脚 |
|--------|------|------|
| EX_IO[0] | Bidir | PIN_J10 |
| EX_IO[1] | Bidir | PIN_J14 |
| EX_IO[2] | Bidir | PIN_H13 |
| EX_IO[3] | Bidir | PIN_H14 |
| EX_IO[4] | Bidir | PIN_F14 |
| EX_IO[5] | Bidir | PIN_E10 |
| EX_IO[6] | Bidir | PIN_D9 |

## 11. 电源

| 参数 | 说明 |
|------|------|
| 输入电压 | 9V DC (桌面电源适配器) |
| 稳压器 | LM3150MH 开关降压稳压器 |
| I/O 电压 | 3.3V / 2.5V / 1.8V / 1.5V 可配置 |

## 12. 兼容的 HSMC 子卡

Terasic 提供以下可与 DE2-115 配合使用的 HSMC 子卡：

| 子卡 | 功能 |
|------|------|
| D5M | 500 万像素摄像头模块 |
| LTM | LCD 触摸屏模块 |
| DVI-HSMC | DVI 数字视频接口 |
| ADA-HSMC | 高速 ADC/DAC 模块 |
| DCC-HSMC | 数字摄像头模块 |
| HTG(M) | 高速传输模块 |
| COMM | 通信模块 |

---

## 13. 引脚总数统计

| 分类 | 引脚数 | 说明 |
|------|--------|------|
| HSMC | 82 | 高速扩展 |
| DRAM | 57 | SDRAM 接口 |
| HEX | 56 | 七段数码管 |
| ENET | 45 | 双千兆以太网 |
| SRAM | 41 | SRAM 接口 |
| FL | 37 | Flash 接口 |
| GPIO | 36 | GPIO 扩展排针 |
| OTG | 30 | USB OTG |
| VGA | 29 | VGA 输出 |
| LED | 27 | LED (9绿+18红) |
| AUD | 6+ | 音频 CODEC |
| SW | 18 | 拨码开关 |
| LCD | 13 | 16x2 LCD |
| TD | 12 | TV 视频输入 |
| SD | 7 | SD 卡 |
| EX | 7 | 扩展 I/O |
| KEY | 4 | 按键 |
| PS2 | 4 | PS/2 双接口 |
| UART | 4 | RS-232 |
| CLOCK | 3 | 50MHz 时钟 |
| I2C | 2+1 | I2C + IRDA |
| EEP | 2 | EEPROM |
| SMA | 2 | 外部时钟 |
| **总计** | **~539** | 有效引脚 |

---

## 14. 做大活儿的潜力评估

这套板子的资源非常丰富，可以实现以下复杂项目：

| 方向 | 可用资源 | 典型应用 |
|------|----------|----------|
| **网络** | 双千兆以太网 | TCP/IP 协议栈、Web 服务器、网络摄像头 |
| **视频** | VGA 输出 + TV 输入 + LCD | 实时视频处理、游戏机、图像识别 |
| **音频** | WM8731 24-bit CODEC | 音频处理器、合成器、FFT 频谱分析 |
| **存储** | SDRAM + SRAM + Flash + SD | 文件系统、大容量数据缓存 |
| **通信** | USB OTG + UART + PS/2 + IR | 键盘/鼠标驱动、USB 设备开发 |
| **显示** | 8个七段数码管 + LCD + VGA + LED | 多层次信息展示 |
| **计算** | 266个硬件乘法器 + 114K LEs | DSP 处理、硬件加速 |
| **扩展** | HSMC + GPIO | 外接摄像头、高速 DAC/ADC |
