# DE2Extra 实施计划 — 硬件 VGA 终端

> 日期: 2026-05-22
> 状态: Draft
> Deadline: 2026-06-15 (板子归还)
> 归档: 旧计划 → `archive/implementation_plan-v1-sof-rtos-gui.md`

## 背景

基于 NEORV32 (RISC-V) 的 FPGA 项目，目标平台 DE2-115 (Cyclone IV E)。
从"一次性跑 13 个 Exp 模块"的想法演变而来，最终方向是一个带硬件密码学加速的 RISC-V 系统。

### 当前已完成

- NEORV32 上板 50MHz，UART/GPIO/LED/HEX/LCD 验证通过
- SDRAM 控制器已实现，存在 hold timing 违例 (TNS = -0.804ns)
- 资源占用: 7,916 LEs (7%), 15 DSPs, 1 PLL / 4
- 已启用 ISA: RV32IMC + Zicsr + Zicntr + Zfinx + Zkne + Zknd + Zknh + Zksed + Zksh + Zbkb + Zbkc + Zbkx
- TRNG 已启用 (3 环形振荡器, 64-bit 采样, 4 级 FIFO)
- Docker 工具链就绪

### 核心决策

- **不做 GUI 框架** (FreeRTOS/LVGL)，改为纯硬件 VGA 文字终端
- FPU 推迟到以后评估（当前 Zfinx 够用）
- 优先级: 密码学平台 > 多模块演示 > 教学展示

---

## 总体方案

```
Phase 1          Phase 2a + 2b (并行)           Phase 3 (合并)
总线+SDRAM  ──→  2a: 密码学终端(C)              ──→  集成+多模块
(硬件基础)        2b: VGA终端+PS/2(VHDL)         (联调+整合)
```

---

## Phase 1: 总线 + SDRAM 可靠

### 1.1 修复 SDRAM Hold Timing

**问题**: `clk_sdram` (100MHz) 域 hold timing 违例 (TNS = -0.804ns)。

**方案**: 50MHz 侧信号在进入 100MHz 域的同步器前先打一拍 (CDC 前置寄存器)。

### 1.2 Wishbone Interconnect (`wb_intercon.vhd`)

通用地址解码，新外设只需在地址表加一行。单 master (NEORV32 XBUS)，多 slave。

**地址空间**:

| 起始地址 | 大小 | 外设 | Phase |
|---|---|---|---|
| 0x01000000 | 128MB | SDRAM | 1 |
| 0xF0000000 | 8KB | VGA 终端 | 3 |
| 0xF0002000 | 4KB | PS/2 键盘 | 3 |
| 0xF0004000 | 4KB | 系统定时器 | 3 (可选) |
| 0xF0006000 | 4KB | 中断控制器 | 3 (可选) |
| 0xF0008000 | 4KB | LCD 控制器 (已实现) | - |
| 0xF0009000 | 4KB | IR 接收器 | 4 (验收后) |
| 0xF000A000 | 4KB | DDS 音频 | 4 (验收后) |
| 0xF000B000 | 4KB | SD 卡 (SPI) | 4 (可选) |

### 1.3 交付验证

`sdram_test` 通过 interconnect 仍然 ALL PASS。

### 1.4 文件变更

| 操作 | 文件 |
|---|---|
| 新建 | `src/rtl/bus/wb_intercon.vhd` |
| 修改 | `src/rtl/de2_115_top.vhd` — 替换硬编码地址解码为 wb_intercon 实例 |
| 修改 | `src/rtl/lib/de2extra_pkg.vhd` — 添加完整地址常量 |
| 修改 | `src/rtl/periph/sdram_ctrl.vhd` — 修复 CDC 同步 |
| 修改 | `par/de2extra.qsf` — 添加新文件 |
| 修改 | `constraints/de2extra.sdc` — 添加 CDC 约束 |

---

## Phase 2a: 密码学终端 — 软件 (可与 2b 并行)

纯 C 软件，不需要额外 VHDL。NEORV32 Crypto ISA 已全部启用。
此阶段仅通过 UART 交互，不涉及 VGA。
**可立即开始**: 现有 UART+IMEM 环境即可开发测试，不依赖 Phase 1。

### 功能

1. **AES-128/256** (Zkne/Zknd): ECB 模式，NIST 测试向量验证
2. **SHA-256/SHA-512** (Zknh): 任意长度消息
3. **SM4** (Zksed): 国密对称加密
4. **SM3** (Zksh): 国密哈希
5. **性能统计**: Zicntr cycle counter 测量周期数
6. **TRNG 验证**: 读取 TRNG 输出，统计频率分布/游程检测，验证随机性
7. **UART CLI**: `aes enc <hex_key> <hex_plain>`

### 编译与烧录流程

```bash
# 1. 编译 (Docker 内)
riscv32-unknown-elf-gcc -O2 -march=rv32imczkne_zknd_zknh_zksed_zksh_zbkb_zbkc_zbkx_zfinx \
  -T link.ld -o app.elf main.c crypto.c

# 2. 生成 .mif (IMEM 初始化)
riscv32-unknown-elf-objcopy -O binary app.elf app.bin
bin2mif app.bin > imem_init.mif        # 自写脚本或用 srec_cat

# 3. Quartus 编译 (自动将 .mif 关联到 IMEM)
# neorv32_wrapper 的 IMEM 通过 .qsf 的 MIF 路径初始化

# 4. 烧录 .sof 到 DE2-115
# 或者用 NEORV32 bootloader 从 UART 引导 (BOOT_MODE=0)
```

### 交付验证

- PC 串口终端运行命令，输出与 NIST/国密测试向量一致
- 性能统计打印 (cycles, time @50MHz)

### AI 分工建议

2a 的全部工作在 `sw/app/crypto_cli/` 目录下，与其他硬件工作零冲突。

---

## Phase 2b: VGA 终端 + PS/2 键盘 — 硬件 (可与 2a 并行)

纯 VHDL，不需要软件配合。可立即开始写代码和仿真，不依赖 Phase 1。
上板验证需要 Phase 1 的 wb_intercon，但模块本身可独立仿真验证。

核心创新点: 用纯硬件实现一个 VGA 文字终端，CPU 只需写字符到缓冲区。

### 2b.1 VGA 文字终端控制器 (`vga_text_terminal.vhd`)

**规格**:
- 分辨率: 640×480@60Hz (pixel clock 25MHz, 50MHz 二分频)
- 文本模式: 80 列 × 25 行
- 字库: 8×16 像素/字符，ASCII 0-127 (可扩展到 255)
- 色彩: 每字符 2 字节 = [字符 ASCII] + [前景 RGB565]，固定背景色
- 虚拟终端: 2 页缓冲区 (F1/F2 切换)，每页 4,000 bytes
- 屏幕缓冲区: 2 × 4,000 × 16bit = 8,000 bytes → 双端口 RAM (M9K)

**工作方式**:
- CPU 写: Wishbone 写入 (addr = 页×8000 + 行×160 + 列×2)，每次写 16-bit (字符+颜色)
  - 页 0 (F1): 0x0000 - 0x1F3F (2000 words)
  - 页 1 (F2): 0x2000 - 0x3F3F (2000 words)
  - 控制寄存器: 0x1000 - 0x1014
- VGA 读: 控制器自动按扫描顺序读当前活动页缓冲区，查字库 ROM，输出 RGB 像素
- 页切换: 写控制寄存器 bit2 切换 F1/F2，零延迟

**寄存器接口 (0xF0000000)**:

| 偏移 | 读/写 | 说明 |
|---|---|---|
| 0x00 | R/W | 文本缓冲区 (字符+颜色, 16-bit, 每页 4KB) |
| 0x1000 | R/W | 光标 X (0-79) |
| 0x1004 | R/W | 光标 Y (0-24) |
| 0x1008 | R/W | 控制寄存器: bit0=enable, bit1=cursor_blink, bit2=page(0=F1,1=F2) |
| 0x100C | R | 状态: bit0=vblank |
| 0x1010 | W | 背景色 RGB565 |
| 0x1014 | W | 清屏 (清当前活动页) |

**资源估算**:
- 文本缓冲区 (2 页): 8,000×16bit → 7-8 块 M9K
- 字库 ROM: 128 字符 × 8×16 bit = 16Kbit → 2 块 M9K (初始化为 .mif)
- VGA 时序生成器: ~200 LEs
- 光标闪烁逻辑: ~50 LEs
- 总计: ~250 LEs + ~10 M9K blocks

### 2b.2 PS/2 键盘控制器 (`ps2_keyboard.vhd`)

**协议**: 11-bit 帧 (start + 8-data + parity + stop)
**功能**: Set 2 扫描码 → ASCII 转换, 16-entry FIFO
**中断**: 数据就绪时产生 IRQ → 连接 NEORV32 `mext_irq_i`

**扩展键处理** (Set 2 多字节序列):
- `E0` 前缀键: 方向键 (↑↓←→), F1-F12, Ctrl, Shift(右)
- `F0` 释放码: `F0 xx` 表示按键释放
- 组合键检测: 软件维护 modifier 状态 (Shift/Ctrl 状态字)，PS/2 控制器只负责转发原始 scan code 到 FIFO，组合键解析在软件层完成

**寄存器接口 (0xF0002000)**:

| 偏移 | 读/写 | 说明 |
|---|---|---|
| 0x00 | R | 数据 (读后清 FIFO)，原始 scan code |
| 0x04 | R | 状态: bit0=data_ready, bit1=fifo_overflow |
| 0x08 | R/W | 中断使能: bit0=data_irq |

**中断路由**:
- PS/2 `data_irq` → 中断控制器 (0xF0006000) IRQ1 → NEORV32 `mext_irq_i`
- 如果暂不实现独立中断控制器: PS/2 `data_irq` 直接通过 OR 门连接 `mext_irq_i`，软件轮询 PS/2 状态寄存器判断中断源

### 2b.1 VGA 文字终端控制器 (`vga_text_terminal.vhd`)

Phase 2 的 UART CLI 在 Phase 3 需要改造为双输出架构：

```
  ┌──────────────┐     ┌──────────────┐
  │  命令解析     │────→│ VGA 输出层   │ → 写 text_buffer (Wishbone)
  │  + 算法执行   │────→│ UART 输出层  │ → printf UART (NEORV32 UART0)
  └──────────────┘     └──────────────┘
```

- VGA: 彩色全功能终端 (命令输出 + 状态栏 + 光标)
- UART: 单色回显，每行前标注来源：
  ```
  【VGA】DE2Extra RISC-V Terminal
  【SYS】AES-128 ECB: time=1234 cycles
  【IN】aes enc 0011..2233 4455..6677
  【ERR】unknown command 'foo'
  ```
- 标签规则: `【VGA】` = VGA 屏幕内容镜像, `【SYS】` = 系统输出, `【IN】` = 用户输入回显, `【ERR】` = 错误
- **UART 输入**: 支持所有命令，效果与 PS/2 键盘等价

软件层面，定义一个统一的 `terminal_putc(char c, color_t color)` 函数，内部同时写 VGA 缓冲区和 UART。

### 2b.4 界面设计

#### 提示符

无权限系统，不伪装 shell。用返回码 + 颜色表示状态：

```
0000 > _          ← 绿色, 上次命令成功
FFFF > _          ← 红色, 上次命令失败
```
`0000` 是成功返回码 (绿色)，`FFFF` 是错误码 (红色)。中间用空格分隔，`>` 后跟光标。

#### 启动画面 (fastfetch 风格)

上电后自动打印系统信息，不输入任何命令：

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

#### 屏幕布局 (80×25)

```
  ┌─────────────────── 行 0-1: 启动/命令输出区 ───────────────────┐
  │                                                               │
  │  命令输出和历史记录，向上滚屏                                    │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  │                                                               │
  ├─────── 行 23: 提示符 ────────────────────────────────────────┤
  │ 0000 > aes enc 0011..2233 4455..6677                         │
  ├─────── 行 24: 状态栏 (固定) ────────────────────────────────┤
  │ DE2Extra │ AES SHA SM4 SM3 TRNG │ 50MHz │ 2026-06-01 12:34 │
  └───────────────────────────────────────────────────────────────┘
```

- 行 0-23: 滚动区域（命令输出）
- 行 23: 提示符行（当前命令输入）
- 行 24: 固定状态栏（硬件时间 + 系统状态）

#### 状态栏 (行 24)

```
 DE2Extra │ AES SHA SM4 SM3 TRNG │ 50MHz │ 2026-06-01 12:34
```
- 左: 项目名（固定）
- 中: 已验证的算法模块（绿色=已验证，黄色=未验证）
- 右: CPU 频率 + 时间

**时间**: 复用 Exp3 电子钟计算逻辑，50MHz 输入 → 计算秒/分/时/日/月/年。
CPU 每 50,000,000 个 cycle 中断一次（或轮询 `mcycle` CSR），更新状态栏右下角时间。
不做闹钟/计时器，只做显示。

#### 虚拟终端 (F1/F2)

- `F1`: 主终端（命令行 + 密码学 demo）
- `F2`: 演示页（可视化的密码学过程 / 实验模块展示 / 实时波形等）
- 按 `F1`/`F2` 键切换，硬件页切换零延迟
- 每页独立光标、独立滚屏历史

### 2b.5 命令设计

```
  命令                参数                              说明
  ─────────────────────────────────────────────────────────────────
  help                                                 打印命令列表
  clear                                                清屏

  aes enc <key> <pt>    key/pt = hex string           AES-128 ECB 加密
  aes dec <key> <ct>    key 16 bytes, pt 16 bytes     AES-128 ECB 解密
  sha256 <msg>          msg = hex string              SHA-256 哈希
  sha512 <msg>          msg = hex string              SHA-512 哈希
  sm4 enc <key> <pt>    key/pt = hex, 16 bytes each   SM4 加密
  sm3 <msg>             msg = hex string              SM3 哈希
  trng [n]              n = bytes, default 16        读取 TRNG 随机数

  bench                                                运行全部性能基准测试
  sdram test                                           SDRAM 读写验证
  info                                                 打印 fastfetch 系统信息

  hex <addr> [n]        addr = 32-bit hex             内存查看 (SDRAM/寄存器)
  led <val>             val = 32-bit hex              控制 LED 输出

  clip                                                 输出剪贴板内容到 UART
  screen                                               输出当前屏幕 80×25 到 UART
```

**剪贴板** (256 bytes, CPU 内存):
- `Shift+方向键`: 选中文字 (蓝色高亮)
- `Ctrl+Shift+C`: 复制选中文字到剪贴板
- `Ctrl+Shift+X`: 剪切选中文字
- `Ctrl+Shift+V`: 在光标处粘贴剪贴板内容
- `clip`: 串口输出剪贴板内容 (AI 调试用)
- `screen`: 串口输出全屏内容 (无需选中，一键导出)
```

- 不支持管道、重定向、后台进程（无 OS）
- 参数格式统一用 hex string，空格分隔
- 错误时返回码置 `FFFF`，UART 输出 `【ERR】` 原因

### 2b.6 交付验证

- VGA 显示彩色文字菜单 + 光标闪烁
- PS/2 键盘输入字符显示在 VGA 上
- 密码学结果从 UART 迁移到 VGA 显示
- 滚屏正常工作

### AI 分工建议

2b 的 VHDL 工作在 `src/rtl/periph/` 目录下，2a 的 C 工作在 `sw/app/` 目录下，文件零冲突。
2b 的 2b.3 (UART/VGA 双输出架构) 和 2b.5 (命令设计) 是两边合并时的接口约定，两个 AI 都需要知道。

---

## Phase 3: 集成 + 多模块整合

**前提**: 只有验收表中标注"已验收"的实验模块才能整合。

### 可挂载模块 (来自验收表)

| 实验模块 | 地址 | 整合方式 | 条件 |
|---|---|---|---|
| Exp8 PS/2 键盘 | 0xF0002000 | 终端输入 (已在 Phase 3) | 已验收 |
| Exp10 IR NEC | 0xF0009000 | 红外遥控扩展输入 | 验收后 |
| Exp13 LCD | 0xF0008000 | 状态栏/第二屏幕 | 已验收 |
| Exp11 DDS | 0xF000A000 | 音频波形输出 (WM8731) | 验收后 |

### 命令扩展

```
  lcd <msg>             msg = ASCII string           LCD 显示指定文字
  ir                                                   等待红外遥控输入并显示
  dds <freq> <wave>     freq=Hz, wave=sin/sq/tri     DDS 音频输出
  screen                                               (已有, 全屏导出)
  info                                                 (已有, 系统信息)
```

### 13 Exp C 版复现 (可选，6/15 后)

用 riscv-gcc 把 13 个实验的核心逻辑改写成 C 版本，作为终端 demo 的子功能：
- 纯组合逻辑实验 (门电路、解码器) → C 函数模拟 + 验证向量对比
- 时序逻辑实验 (计数器、FSM) → C 状态机实现
- 外设实验 (UART/SPI/I2C/LCD) → 调用 NEORV32 驱动
- 优势: 效果直观、可交互、代码可维护，比 VHDL testbench 更适合演示

---

## 时间线 (6/15 前)

| 周次 | 工作内容 |
|---|---|
| 5/22-5/25 | Phase 1: SDRAM timing 修复 + wb_intercon |
| 5/22-6/01 | Phase 2a: 密码学终端 C 软件 (可与 2b 并行) |
| 5/22-6/01 | Phase 2b: VGA + PS/2 VHDL (可与 2a 并行) |
| 6/02-6/08 | Phase 3: 2a+2b 集成，UART/VGA 双输出，已验收模块挂载 |
| 6/09-6/13 | Phase 3 (续): 联调 + 剪贴板 + 演示页 F2 |
| 6/14-6/15 | 收尾: 文档、演示准备 |

---

## 资源预算

| 模块 | LEs | M9K | DSP | 备注 |
|---|---|---|---|---|
| NEORV32 (现有) | ~2,300 | ~40 | ~15 | |
| SDRAM 控制器 (现有) | ~1,500 | ~5 | 0 | |
| wb_intercon | ~200 | 0 | 0 | |
| VGA 终端 (2页) | ~300 | ~10 | 0 | 2 页缓冲 16KB |
| PS/2 键盘 | ~150 | ~1 | 0 | |
| LCD (现有) | ~200 | 0 | 0 | |
| **合计** | **~4,600** | **~56** | **15** | |
| **板载总量** | 114,480 | 432 | 266 | |
| **占用率** | **~4%** | **~13%** | **~6%** | 资源非常充裕 |

---

## 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| SDRAM timing 修复不彻底 | Phase 1 延期 | 先用简单方案 (降频) 保证基本功能 |
| 字库 ROM 初始化 .mif 格式问题 | VGA 显示乱码 | 从开源项目复制已知可用的字库 |
| PS/2 协议时序 | 键盘输入丢码 | 用 FIFO 缓冲 + 重试机制 |
| 6/15 时间不足 | Phase 4 做不完 | Phase 1-3 是核心，Phase 4 按时间灵活 |
