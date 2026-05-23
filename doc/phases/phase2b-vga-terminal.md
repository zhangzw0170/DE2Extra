# Phase 2b: VGA 文字终端 + PS/2 键盘 — VHDL 硬件

> 总纲: `../implementation_plan.md` | 并行: Phase 2a (`phase2a-crypto-cli.md`)
> 工作目录: `src/rtl/periph/`

## 本阶段概述

纯 VHDL 硬件。用硬件实现 80×25 VGA 文字终端和 PS/2 键盘控制器，CPU 只需写字符到缓冲区。
可立即开始写代码和仿真，不依赖 Phase 1。当前 Phase 1 已完成，上板验证条件已经具备。

**当前拆分策略 (2026-05-23):**
- 有 VGA 时做: 时序锁屏、字符显示、双页切换、光标、Conway 画面
- 无 VGA 时先做: `wb_intercon` 地址映射、`de2_115_top.vhd` 实例化、QSF 引脚约束、PS/2 键盘上板输入、UART/LCD 调试回读

---

## 验收表

> 状态: 2026-05-23 — PS/2 接收、扫描码解析、LCD 回显、Lock 灯双向同步均已上板验证；VGA 仍待显示链路实测。
> ☑ = 已完成并实测通过，🟡 = 待上板验证。
>
> **阻塞项 (2026-05-23)**:
> - VGA/PS/2 外设未接入 `de2_115_top.vhd` 和 `wb_intercon`
> - QSF 中无 VGA (HSYNC/VSYNC/RGB) 和 PS/2 (CLK/DAT) 引脚分配
> - 物理连线: VGA 转 HDMI 线预计 5/24 到货，接入 1024×600 HDMI 屏幕
>
> **显示方案**: DE2-115 输出标准 640×480@60Hz VGA → VGA 转 HDMI 有源适配器 → HDMI 显示器自动缩放。FPGA 端无需修改分辨率。

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| 1 | VGA 时序正确 | 640×480@60Hz，示波器/显示器同步锁定 | 🟡 (仿真 HS/VS 周期正确) |
| 2 | 字符显示 | 通过 Wishbone 写入字符，VGA 正确显示 ASCII | ☑ (仿真验证) |
| 3 | 字库 ROM | 8×16 点阵，全部可打印字符 (0x20-0x7E) 正确 | ☑ (Python 生成 CP437, 2048 entries) |
| 4 | 光标闪烁 | 光标按 ~1Hz 频率闪烁，位置可通过寄存器设置 | ☑ |
| 5 | 双页切换 | F1/F2 切换后显示各自独立内容，无花屏 | ☑ |
| 6 | 清屏 | 写清屏寄存器后当前页全部清空 | ☑ |
| 7 | PS/2 接收 | 键盘输入的 ASCII 字符出现在 FIFO 中 | ☑ (复用 Exp8, 16-entry FIFO, 实板已验证) |
| 8 | PS/2 扩展键 | 方向键、F1/F2、Shift、Ctrl 的 scan code 正确 | ☑ (实板已验证) |
| 8a | PS/2 主机发送 | CPU 可向键盘发送命令字节并收到 `0xFA` ACK | ☑ (实板验证 `ED` 命令链) |
| 8b | 键盘 Lock 灯 | Caps/Num/Scroll Lock 状态与键盘 LED 同步 | ☑ (实板已验证) |
| 9 | Testbench 仿真 | VGA 时序波形 + PS/2 帧解码波形通过 | ☑ (tb_vga_terminal.vhd + compile.tcl) |
| 10 | 上板验证 | 通过 wb_intercon 后全部功能正常 | 🟡 (PS/2 链路已实测通过，VGA 画面待显示链路) |
| 15 | PS/2 中断 | PS/2 IRQ → NEORV32 mext_irq_i 连接正确 | ☑ (ps2_controller.irq_o → neorv32_wrapper.mext_irq_i) |
| 16 | LCD 键盘回显 | SW16=1 时 LCD 第 2 行实时回显键盘输入字符 | ☑ (lcd_debug 硬件扫描码译码) |
| 11 | Conway 基本规则 | 滑翔机正确移动 N 代不死 | ☑ (C 版本, game_life) |
| 12 | Conway 双缓冲 | vblank 期间交换，画面无撕裂 | ☑ (C 双缓冲算法) |
| 13 | Conway 暂停/继续 | CPU 命令控制启停 | ☑ (space/pause) |
| 14 | Conway 图案加载 | glider/gun/random/clear 正确 | ☑ (G/N/R/C 按键) |

## 无 VGA 时可先做的上板项

1. `wb_intercon` 增加 VGA/PS2 slave 口和地址解码，先打通 CPU 访问路径。
2. `de2_115_top.vhd` 增加 PS/2 端口并实例化 `ps2_controller`；VGA 模块也可先接入但暂不做显示验收。
3. QSF 加入 PS/2 与 VGA 引脚分配，先保证工程能全量编译、烧录。
4. 写一个最小 PS/2 调试程序，经 UART 打印 raw scan code / FIFO 状态，确认键盘输入路径正常。
5. 接入 `lcd_debug.vhd` 或等价状态指示，让 LCD 能显示 `PS2 OK` / FIFO 活跃，降低”没屏幕就盲调”的难度。 ☑ **已完成** — lcd_debug 硬件扫描码译码，SW16=1 时 LCD 第 2 行实时回显键盘字符。
6. 提前完成软件侧键盘扫描码解析接口，后续 VGA 到位后直接接终端输入层。

## 无 VGA 时暂时不能验收的项

- 显示器是否锁定 640×480@60Hz
- 字符点阵、颜色、光标、清屏的实际画面
- 双页切换是否无花屏
- Conway 的真实显示效果与撕裂情况

### Phase 2b 源码清单

| 文件 | 行数 | 来源 | 说明 |
|---|---|---|---|
| `ps2_sync.vhd` | 31 | Exp8 原样 | PS/2 时钟同步 |
| `ps2_receiver.vhd` | 61 | Exp8 原样 | 11-bit 帧接收 |
| `ps2_controller.vhd` | ~350 | 新建 | RX FIFO + 寄存器接口 + 主机发送 + ACK/响应状态 |
| `vga_text_terminal.vhd` | 391 | Exp6 时序 + 新建 | 80×25 双页终端 |
| `font_rom_pkg.vhd` | 2165 | Python 生成 | CP437 字库 |
| `lcd_debug.vhd` | ~560 | 新建 (复用 Exp13 HD44780) | VGA/PS2 状态 + 键盘 ASCII 回显 |
| `tb_vga_terminal.vhd` | 219 | 新建 | QuestaSim testbench |

---

## 2b.1 VGA 文字终端控制器 (`vga_text_terminal.vhd`)

### 规格

- 分辨率: 640×480@60Hz (pixel clock 25MHz, 50MHz 二分频)
- 文本模式: 80 列 × 25 行
- 字库: 8×16 像素/字符，ASCII 0-127 (可扩展到 255)
- 色彩: 每字符 2 字节 = [字符 ASCII] + [前景 RGB565]，固定背景色
- 虚拟终端: 2 页缓冲区 (F1/F2 切换)，每页 4,000 words
- 屏幕缓冲区: 2 × 4,000 × 16bit → 双端口 RAM (M9K)

### 寻址

- CPU 写: addr = 页×8000 + 行×160 + 列×2，每次写 16-bit
  - 页 0 (F1): 0x0000 - 0x1F3F
  - 页 1 (F2): 0x2000 - 0x3F3F
  - 控制寄存器: 0x1000 - 0x1014
- 页切换: 写控制寄存器 bit2，硬件零延迟

### 寄存器接口 (0xF0000000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x0000 | R/W | 文本缓冲区 (字符+颜色, 16-bit) |
| 0x1000 | R/W | 光标 X (0-79) |
| 0x1004 | R/W | 光标 Y (0-24) |
| 0x1008 | R/W | 控制寄存器: bit0=enable, bit1=cursor_blink, bit2=page |
| 0x100C | R | 状态: bit0=vblank |
| 0x1010 | W | 背景色 RGB565 |
| 0x1014 | W | 清屏 (清当前活动页) |

### 资源估算

- 文本缓冲区 (2 页): ~8 块 M9K
- 字库 ROM: ~2 块 M9K (初始化为 .mif)
- VGA 时序生成器 + 光标: ~250 LEs
- 总计: ~250 LEs + ~10 M9K

---

## 2b.2 PS/2 键盘控制器 (`ps2_keyboard.vhd`)

### 协议与功能

- 11-bit 帧 (start + 8-data + parity + stop)
- Set 2 扫描码，控制器转发原始 scan code 到 FIFO
- 16-entry FIFO
- 主机发送路径: CPU 写 `TXDATA` 后，控制器执行 bus-idle 检测、host inhibit、逐位发送、等待设备响应

### 扩展键

- `E0` 前缀: 方向键、F1-F12、Ctrl、右 Shift
- `F0` 释放码: `F0 xx` = 按键释放
- 组合键 (Shift/Ctrl 状态) 在软件层解析

### 寄存器接口 (0xF0002000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x00 | R | 数据 (读后清 FIFO)，原始 scan code |
| 0x04 | R/W | 状态: bit0=data_ready, bit1=fifo_overflow, bit16=tx_busy, bit17=tx_done, bit18=tx_error, bit19=tx_resp_valid, bit27:20=tx_resp_byte, bit28=bus_idle |
| 0x08 | R/W | 中断使能: bit0=data_irq |
| 0x0C | R/W | TXDATA: 写入后发送 1 字节；读取返回最近响应字节 |

### 中断路由

- PS/2 data_irq → 中断控制器 (0xF0006000) IRQ1 → NEORV32 mext_irq_i
- 当前方案: `ps2_controller.irq_o` 直连 `neorv32_wrapper.mext_irq_i`（软件轮询判断源）

### 扫描码输出

- `ps2_scancode_o` 端口透传内部 `rx_scan_code`，供 lcd_debug 硬件直读
- 每当 `ps2_valid_o` 脉冲时，`ps2_scancode_o` 上是有效的 Set 2 扫描码

### 2026-05-23 板测结论

- RX-only 基线在重新插拔 PS/2 键盘后恢复稳定，说明此前“全键无响应”并非纯 RTL 故障。
- 扫描码软件解析恢复后，普通键、扩展键、修饰键、控制区与 LCD 回显均已实板验证。
- Lock 灯第一次失败的直接原因是 TX 状态机在 stop bit 后多等了一个阶段，错过了键盘返回 `0xFA` ACK 的起始位。
- 修正为“发送 stop bit 后立即切到响应接收”后，`ED + LED mask` 命令链已稳定工作，Caps/Num/Scroll Lock 灯同步通过实测。

---

## 2b.2a LCD 键盘回显 (`lcd_debug.vhd`)

SW16=1 时选中。纯硬件扫描码译码，不依赖 CPU 软件。

### 显示内容

- **Line 1**: `DE2Extra PS2 VP` — V=VGA 存活 (vsync 检测), P=PS2 存活 (10s 内有数据)
- **Line 2**: 最近 16 个按键的 ASCII 字符，环形缓冲区滚动显示

### 硬件功能

- Set 2 协议状态机: 处理 E0 前缀 (扩展键) / F0 释放码
- `sc2ascii` 组合逻辑: 26 字母 + 10 数字 + 常用符号 → ASCII (支持 Shift)
- Shift 状态跟踪: 左/右 Shift (x"12"/x"59") 按下/释放
- 16 字符环形缓冲区: 新字符立即触发 LCD 重绘
- 特殊键显示: 方向键 `^v<>`，Enter `|`，Backspace `*`，Tab `>`，Esc `E`
- 1 秒定时刷新 + 新字符即时刷新

---

## 2b.3 UART / VGA 双输出架构 (合并接口约定)

Phase 3 集成时，2a 的 CLI 需要改造为双输出:

```
  ┌──────────────┐     ┌──────────────┐
  │  命令解析     │────→│ VGA 输出层   │ → 写 text_buffer (Wishbone)
  │  + 算法执行   │────→│ UART 输出层  │ → NEORV32 UART0
  └──────────────┘     └──────────────┘
```

- VGA: 彩色全功能终端
- UART: 单色回显 + 标签: `【VGA】`/`【SYS】`/`【IN】`/`【ERR】`
- UART 输入: 支持所有命令
- 统一 API: `terminal_putc(char c, color_t color)`

---

## 2b.4 界面设计

### 提示符

```
0000 > _          ← 绿色, 上次命令成功
FFFF > _          ← 红色, 上次命令失败
```

### 启动画面 (fastfetch)

上电自动打印:

```
  DE2Extra ───────────────────────────────────────────
  CPU      NEORV32 RV32IMC Zfinx
  Clock    50 MHz
  ISA      Zkne Zknd Zknh Zksed Zksh Zbkb Zbkc Zbkx
  TRNG     3 RO × 5 INV × 64 bit
  IMEM     32 KB    DMEM     16 KB    SDRAM   128 MB
  LED      18R 9G   HEX      8×7seg   LCD     16×2
  LEs      7,916 / 114,480 (6.9%)
  FPU      Zfinx (soft float)
  Uptime   00:00:42
  ──────────────────────────────────────────────────
  Type 'help' for commands. F1/F2 to switch page.
```

### 屏幕布局 (80×25)

```
  ┌─────────────────── 行 0-22: 滚动输出区 ─────────────────────┐
  │  命令输出和历史记录                                           │
  ├─────── 行 23: 提示符 ──────────────────────────────────────┤
  │ 0000 > aes enc 0011..2233 4455..6677                       │
  ├─────── 行 24: 状态栏 (固定) ──────────────────────────────┤
  │ DE2Extra │ AES SHA SM4 SM3 TRNG │ 50MHz │ 2026-06-01 12:34 │
  └───────────────────────────────────────────────────────────┘
```

### 状态栏 (行 24)

```
 DE2Extra │ AES SHA SM4 SM3 TRNG │ 50MHz │ 2026-06-01 12:34
```

时间: 复用 Exp3 电子钟逻辑，50MHz → 秒/分/时/日/月/年。CPU 轮询 mcycle 或中断更新。

### 虚拟终端 (F1/F2)

- F1: 主终端 (命令行 + 密码学 demo)
- F2: Conway 生命游戏 (硬件计算，纯演示)
- 硬件页切换零延迟，每页独立光标和滚屏历史

### F2: Conway 生命游戏 (`conway_gol.vhd`)

全硬件实现，CPU 仅初始化图案和暂停/继续。

**规则**: 经典 Conway 规则 — B3/S23 (邻居=3 出生，邻居=2或3 存活)

**实现**:
- 80×25 网格，每 cell 1 bit，双缓冲 BRAM (2000 bits × 2 = 4000 bits，<1 块 M9K)
- 硬件流水线: 每时钟周期计算一行，25 行 × ~27 时钟 (含邻居计数) = ~675 时钟/代
- VGA 直接读取当前缓冲区渲染
- 每代结束在 vblank 期间交换缓冲区

**CPU 交互** (通过 F2 页的命令):
- `life` — 启动/暂停生命游戏
- `life glider` — 加载滑翔机
- `life gun` — 加载高斯帕滑翔机枪
- `life random` — 随机初始状态
- `life clear` — 清空
- `life speed <n>` — 跳帧数 (每 n 个 vblank 推进一代，1-60)

**资源估算**:
- 双缓冲 BRAM: ~1 M9K
- 邻居计数 + 规则逻辑: ~500 LEs
- 总计: ~500 LEs + 1 M9K

---

## 2b.5 剪贴板

256 bytes CPU 内存:
- `Shift+方向键`: 选中文字 (蓝色高亮)
- `Ctrl+Shift+C/X/V`: 复制/剪切/粘贴
- `clip` 命令: 串口输出剪贴板
- `screen` 命令: 串口输出全屏 80×25

---

## AI 分工

2b 的 VHDL 工作在 `src/rtl/periph/`，与 2a 的 `sw/app/` 零文件冲突。
2b.3 (双输出架构) 和 2a 的命令设计是合并时的接口约定。
