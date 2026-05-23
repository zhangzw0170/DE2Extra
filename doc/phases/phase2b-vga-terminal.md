# Phase 2b: VGA 文字终端 + PS/2 键盘 — VHDL 硬件

> 总纲: `../implementation_plan.md` | 并行: Phase 2a (`phase2a-crypto-cli.md`)
> 工作目录: `src/rtl/periph/`

## 本阶段概述

纯 VHDL 硬件。用硬件实现 80×25 VGA 文字终端和 PS/2 键盘控制器，CPU 只需写字符到缓冲区。
可立即开始写代码和仿真，不依赖 Phase 1。上板验证需要 Phase 1 的 wb_intercon。

---

## 验收表

> 状态: 2026-05-23 — 源码完成，QuestSim testbench 可验证。上板验证等待 Phase 1。
> ☑ = 源码完成（已在 QuestaSim 验证时序），🟡 = 待上板验证。

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| 1 | VGA 时序正确 | 640×480@60Hz，示波器/显示器同步锁定 | 🟡 (仿真 HS/VS 周期正确) |
| 2 | 字符显示 | 通过 Wishbone 写入字符，VGA 正确显示 ASCII | ☑ (仿真验证) |
| 3 | 字库 ROM | 8×16 点阵，全部可打印字符 (0x20-0x7E) 正确 | ☑ (Python 生成 CP437, 2048 entries) |
| 4 | 光标闪烁 | 光标按 ~1Hz 频率闪烁，位置可通过寄存器设置 | ☑ |
| 5 | 双页切换 | F1/F2 切换后显示各自独立内容，无花屏 | ☑ |
| 6 | 清屏 | 写清屏寄存器后当前页全部清空 | ☑ |
| 7 | PS/2 接收 | 键盘输入的 ASCII 字符出现在 FIFO 中 | ☑ (复用 Exp8, 16-entry FIFO) |
| 8 | PS/2 扩展键 | 方向键、F1/F2、Shift、Ctrl 的 scan code 正确 | ☑ (Exp8 已验证) |
| 9 | Testbench 仿真 | VGA 时序波形 + PS/2 帧解码波形通过 | ☑ (tb_vga_terminal.vhd + compile.tcl) |
| 10 | 上板验证 | 通过 wb_intercon (Phase 1) 后全部功能正常 | 🟡 (等待 Phase 1) |
| 11 | Conway 基本规则 | 滑翔机正确移动 N 代不死 | ☑ (C 版本, game_life) |
| 12 | Conway 双缓冲 | vblank 期间交换，画面无撕裂 | ☑ (C 双缓冲算法) |
| 13 | Conway 暂停/继续 | CPU 命令控制启停 | ☑ (space/pause) |
| 14 | Conway 图案加载 | glider/gun/random/clear 正确 | ☑ (G/N/R/C 按键) |

### Phase 2b 源码清单

| 文件 | 行数 | 来源 | 说明 |
|---|---|---|---|
| `ps2_sync.vhd` | 31 | Exp8 原样 | PS/2 时钟同步 |
| `ps2_receiver.vhd` | 61 | Exp8 原样 | 11-bit 帧接收 |
| `ps2_controller.vhd` | 202 | 新建 | FIFO + 寄存器接口 |
| `vga_text_terminal.vhd` | 391 | Exp6 时序 + 新建 | 80×25 双页终端 |
| `font_rom_pkg.vhd` | 2165 | Python 生成 | CP437 字库 |
| `lcd_debug.vhd` | 368 | 新建 (复用 Exp13 HD44780) | VGA/PS2 状态指示 |
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

### 扩展键

- `E0` 前缀: 方向键、F1-F12、Ctrl、右 Shift
- `F0` 释放码: `F0 xx` = 按键释放
- 组合键 (Shift/Ctrl 状态) 在软件层解析

### 寄存器接口 (0xF0002000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x00 | R | 数据 (读后清 FIFO)，原始 scan code |
| 0x04 | R | 状态: bit0=data_ready, bit1=fifo_overflow |
| 0x08 | R/W | 中断使能: bit0=data_irq |

### 中断路由

- PS/2 data_irq → 中断控制器 (0xF0006000) IRQ1 → NEORV32 mext_irq_i
- 降级方案: 直接 OR 门连接 mext_irq_i，软件轮询判断源

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
