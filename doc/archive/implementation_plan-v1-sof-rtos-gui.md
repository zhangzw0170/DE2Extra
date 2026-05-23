# DE2Extra 分层交付路线设计

> 日期: 2026-05-22
> 状态: Approved

> **重要约束 — 模块复用前提**: 本设计中所有标注"来自验收表的复用模块"（PS/2 键盘、IR NEC、LCD、DDS、VGA 等），**只有在验收表中标注"已验收"后才允许整合进 DE2Extra**。开发过程中参考已有实验代码时，必须先确认其验收状态，防止整合一个未经验证的模块导致问题难以定位。此约束贯穿所有里程碑 (M1-M6)，不限于 M5。

## 背景

DE2Extra 是一个基于 NEORV32 (RISC-V) 的 FPGA 全外设操作系统级项目，目标平台为 DE2-115 (Cyclone IV E) 和达芬奇 A7Pro。

### 当前状态

- **Phase 0 已完成**: NEORV32 CPU 上板 50MHz，UART/GPIO 验证通过，Docker 工具链就绪
- **Phase 1 部分**: SDRAM 控制器已实现，但存在 Hold timing 违例 (TNS = -0.804ns)
- **资源占用**: 7,916 LEs (7%), 15 DSPs, 1 PLL / 4
- **已启用 ISA 扩展**: RV32IMC + Zicsr + Zicntr + Zfinx + Zkne + Zknd + Zknh + Zksed + Zksh + Zbkb + Zbkc + Zbkx

### 约束

- 性质: 探索性，无紧急截止日期
- 硬件: DE2-115 + 达芬奇 A7Pro 均有
- 优先级: 密码学平台 > 完整计算机体验 > 教学展示
- 验收表独立于 DE2Extra，不纳入范围

---

## 总体路线: 方案 C — 分层交付

每步都有可演示的成果，风险分散，密码学最先出来。

```
M1 总线+SDRAM ──→ M2 密码学终端 ──→ M3 最小GUI ──→ M4 完整GUI ──→ M5 密码学可视化+整合 ──→ M6 A7Pro移植
    (硬件基础)      (纯软件)        (VGA+PS/2)     (FreeRTOS+LVGL)   (密码学UI+实验)       (跨平台)
```

---

## M1: 总线 + SDRAM 可靠

### 目标

- 修复 SDRAM Hold timing 违例
- 实现通用 Wishbone interconnect
- SDRAM 通过 interconnect 正常工作

### SDRAM Hold Timing 修复

**问题**: `clk_sdram` (100MHz) 域 Hold timing 违例，原因是在 50MHz 侧的信号直接进入 100MHz 同步器时 hold 裕量不足。

**方案**: 在 50MHz 侧先打一拍再过 100MHz 域（CDC 前置寄存器），确保 100MHz 侧有足够的 hold 裕量。在 `de2_115_top.vhd` 中 WB 信号进入 `sdram_ctrl` 前经过 50MHz 寄存。

### Wishbone Interconnect (`wb_intercon.vhd`)

**设计原则**:
- 通用地址解码，新外设只需在地址表加一行
- 单 master (NEORV32 XBUS)，多 slave
- 未映射地址返回 bus error

**地址空间**:

| 起始地址 | 大小 | 外设 | 里程碑 |
|---|---|---|---|
| 0x01000000 | 128MB | SDRAM | M1 |
| 0xF0000000 | 4KB | VGA 控制器 | M3 |
| 0xF0001000 | 4KB | PS/2 键盘 | M3 |
| 0xF0002000 | 4KB | PS/2 鼠标 | M4 |
| 0xF0003000 | 4KB | 系统定时器 | M4 |
| 0xF0004000 | 4KB | 中断控制器 | M4 |
| 0xF0007000 | 4KB | DDS 音频 | M5 |
| 0xF0008000 | 4KB | LCD 控制器 | M5 |
| 0xF0009000 | 4KB | IR 接收器 | M5 |

**接口**: Wishbone Classic，与 NEORV32 XBUS 直接兼容。

**交付验证**: `sdram_test` 通过 interconnect 仍然 ALL PASS。

---

## M2: 密码学终端 (纯 UART 交互)

### 目标

在 M1 的基础上，纯软件实现密码学算法演示，通过 UART 交互。不需要额外 VHDL 硬件。

### 为什么不需要额外硬件

NEORV32 的 Crypto ISA 扩展已全部启用:
- Zkne/Zknd: AES-128/256 加密/解密
- Zknh: SHA-256/SHA-512
- Zksed: SM4 (国密对称加密)
- Zksh: SM3 (国密哈希)
- Zbkb/Zbkc/Zbkx: 底层位操作原语

这些都是 CPU 指令，C 代码通过内联汇编或 intrinsics 调用。

### 功能

1. **AES-128/256**: ECB 模式，NIST 测试向量验证
2. **SHA-256/SHA-512**: 任意长度消息，NIST 测试向量验证
3. **SM4/SM3**: 国密标准测试向量验证
4. **性能统计**: 利用 Zicntr (cycle counter) 测量算法周期数
5. **UART CLI**: 命令解析，如 `aes enc <hex_key> <hex_plain>`

### 不需要

- 无 VGA/LVGL/FreeRTOS
- 无额外 VHDL 模块
- 无外部存储（16KB DMEM 足够测试）

### 交付验证

- PC 串口终端运行命令，AES/SHA/SM4/SM3 输出与 NIST/国密测试向量一致
- 性能统计打印 (cycles, time @50MHz)

---

## M3: 最小 GUI (VGA + PS/2 键盘)

### 目标

让 DE2-115 出现图形界面，不引入 FreeRTOS 和 LVGL。直接在 SDRAM 帧缓冲上画像素。

### VGA 分辨率: 640x480@60Hz

**不搞 720p 的原因**:
- 720p pixel clock = 74.25MHz，50MHz PLL 无法整数倍生成
- 640x480 pixel clock = 25.175MHz，使用 50MHz 二分频得 25MHz（误差 0.7%，VGA 显示器容差 ±0.5%，实际可用）
- 640x480 帧缓冲: 640 x 480 x 2 (RGB565) = 614,400 bytes ≈ 600KB
- SDRAM 带宽需求: 25MHz x 2 = 50MB/s，对 200MB/s SDRAM 很轻松

### VGA 控制器 (`vga_controller.vhd`)

**时序参数 (640x480@60Hz)**:
- H_TOTAL=800, H_SYNC=96, H_BP=48, H_FP=16
- V_TOTAL=525, V_SYNC=2, V_BP=33, V_FP=10
- Pixel clock: 25MHz (50MHz / 2)

**帧缓冲模式**: 单缓冲 + 软件同步。软件轮询 VGA 控制器的 status 寄存器 (`[0x10]`) 中的 `vblank` 位，在垂直消隐期间写入帧缓冲，避免画面撕裂。

**寄存器接口 (0xF0000000)**:
- `[0x00]` 帧缓冲基址 (R/W)
- `[0x04]` 控制寄存器: bit0=enable, bit1=cursor_visible (R/W)
- `[0x08]` 光标 X (R/W)
- `[0x0C]` 光标 Y (R/W)
- `[0x10]` 状态寄存器: bit0=vblank (R)

### PS/2 键盘控制器 (`ps2_keyboard.vhd`)

**协议**: 11-bit 帧 (start + 8-data + parity + stop)
**功能**: Set 2 扫描码 → ASCII 转换, 16-entry FIFO
**中断**: 数据就绪时产生 IRQ

**寄存器接口 (0xF0001000)**:
- `[0x00]` 数据 (R), 读后清 FIFO
- `[0x04]` 状态: bit0=data_ready, bit1=fifo_overflow (R)
- `[0x08]` 中断使能: bit0=data_irq (R/W)

### 软件层

- 裸机循环，无 RTOS
- 帧缓冲直写 (RGB565)
- 8x16 点阵字库渲染 ASCII 文字
- 简单文本菜单 (类似 BIOS SETUP)
- 密码学结果从 UART 迁移到 VGA 显示

### 交付验证

- VGA 显示色条 + 文字菜单
- PS/2 键盘输入字符显示在 VGA 上
- 密码学结果在 VGA 上显示

---

## M4: 完整 GUI (FreeRTOS + LVGL)

### 目标

在 M3 硬件基础上加 FreeRTOS + LVGL，实现真正的图形界面。

### 新增硬件

#### 系统定时器 (`timer_module.vhd`) — 0xF0003000

- 32-bit 可配置定时器，1ms tick (configTICK_RATE_HZ = 1000)
- 寄存器: `[0]=count, [4]=reload, [8]=control, [C]=status`

#### 中断控制器 (`interrupt_ctrl.vhd`) — 0xF0004000

- 8 级优先级中断仲裁
- 寄存器: `[0]=pending, [4]=enable, [8]=vector, [C]=ack`
- 输出 `irq_o` 连接 NEORV32 的 `mext_irq_i`

**中断源映射**:

| IRQ | 来源 | 优先级 |
|---|---|---|
| 0 | 系统定时器 (tick) | 最高 |
| 1 | PS/2 键盘 | 高 |
| 2 | PS/2 鼠标 | 中 |
| 3 | UART | 中 |
| 4 | VGA VSync | 低 |
| 5-7 | 保留 | - |

#### PS/2 鼠标 (`ps2_mouse.vhd`) — 0xF0002000

- 3-byte 数据包 (dx, dy, buttons)
- 寄存器: `[0]=data, [4]=status, [8]=ctrl`

### FreeRTOS 移植

- `port.c` 上下文切换: 使用 CLINT (MTIMER) 做 tick
- 堆: SDRAM（128MB）
- 临界区: `csrwi mie, 0` / `csrwi mie, MIE_MEXT`
- 任务:
  - Task GUI (LVGL 刷新) — 最高优先级
  - Task Crypto (密码学计算)
  - Task Input (PS/2 处理)

### LVGL 配置

- 单色/有限色 (减少渲染负载)
- 1-2 种字体 (8px + 12px)
- 无动画
- 部分刷新 (dirty rect)
- 帧缓冲直写 (`lv_disp_flush_cb` → SDRAM)

### 性能风险评估

NEORV32 @50MHz 运行 LVGL 是瓶颈。缓解:
- 减少 LVGL 特性
- CPU 空闲时做渲染
- 如果 50MHz 不够，PLL 升频到 100MHz

### 交付验证

- LVGL 界面正常显示 (按钮、文本、滚动)
- PS/2 鼠标控制光标
- 多任务切换 (至少 3 个任务同时运行)

---

## M5: 密码学可视化 + 实验整合

### 密码学 LVGL 界面

将 M2 的密码学功能从 UART 迁移到 LVGL，包含:
- 算法选择 (AES-128/256, SHA-256/512, SM4, SM3)
- 输入区 (键盘输入明文/密钥)
- 执行按钮
- 结果显示 (十六进制)
- 性能统计 (周期数、时间)

### 实验整合

**前提条件**: 只有验收表中标注"已验收"的实验模块才能整合。整合前需确认该模块已通过板级验证。

**可复用模块 (来自验收表)**:

| 实验模块 | 复用条件 | DE2Extra 地址 | 整合角色 |
|---|---|---|---|
| Exp8 PS/2 键盘 | 已验收 | 0xF0001000 | LVGL 键盘输入 (已在 M3) |
| Exp10 IR NEC | 验收后 | 0xF0009000 | 红外遥控扩展输入 |
| Exp13 LCD | 已验收 | 0xF0008000 | 状态信息显示 (第二屏幕) |
| Exp11 DDS | 验收后 | 0xF0007000 | 音频波形 (连接 WM8731) |

**整合方式**: LVGL 主菜单 → 选择功能 → 启动 FreeRTOS 任务。

---

## M6: 达芬奇 A7Pro 移植 + 优化

### A7Pro 移植

按 DE2Extra 的平台无关设计:
1. 新建 `a7pro_top.vhd` (替代 `de2_115_top.vhd`)
2. 替换引脚约束 (`constraints/`)
3. 替换 PLL 配置
4. 外设模块 VHDL **零修改**

### 性能优化

- SDRAM burst 读取 (帧缓冲)
- NEORV32 ICACHE_EN = true
- LVGL 部分刷新优化
- 可选: XCFU 自定义指令协处理器加速密码学

### 交付验证

- A7Pro 上所有功能正常运行
- 性能对比 (DE2-115 vs A7Pro)

---

## 文件变更清单 (M1)

| 操作 | 文件 |
|---|---|
| 新建 | `src/rtl/bus/wb_intercon.vhd` |
| 修改 | `src/rtl/de2_115_top.vhd` — 替换硬编码地址解码为 wb_intercon 实例 |
| 修改 | `src/rtl/lib/de2extra_pkg.vhd` — 添加完整地址常量 |
| 修改 | `src/rtl/periph/sdram_ctrl.vhd` — 修复 CDC 同步 |
| 修改 | `par/de2extra.qsf` — 添加新文件 |
| 修改 | `constraints/de2extra.sdc` — 添加 CDC 约束 |
