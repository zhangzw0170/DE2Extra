# DE2Extra 游戏总览

DE2-115 FPGA 游戏平台上的所有游戏实现。涵盖纯软件、硬件加速两种模式，V2 (de2shell) 和 V3 (de2os/de2shell_rtos) 两代固件。

## 平台能力

| 资源 | 规格 |
|------|------|
| CPU | NEORV32 RV32IMC @50MHz，无 FPU |
| 显示 | VGA 640×480@60Hz，文本模式 80×30 + 像素模式 RGB332 (8bpp 256色) |
| 输入 | PS/2 键盘（V3 主输入）、UART 串口、红外遥控 |
| 内存 | DMEM 16KB + SDRAM 128MB |
| 音频 | DDS 预留地址 0xF000D000（未实装，游戏暂无音效） |

### 显示模式

**文本模式**（当前主力）：80 列 ×30 行 CP437 字符终端，每个字符带 16 色前景/背景。游戏用 box-drawing 字符拼出画面，`vga_hal.c` 提供抽象层。

**像素模式**（V3 像素 GUI）：640×480 线性帧缓冲，RGB332 调色板，`fb_hal.c` 提供抽象层。V3 的 Win 3.0 桌面和 ChromaShader 使用此模式。

---

## 游戏列表

### 1. Snake（贪吃蛇）

**最成熟的文本模式游戏，V2/V3 双版本可用。**

| 属性 | 值 |
|------|-----|
| 文件 | `sw/app/de2shell/snake.c` (273 行) |
| 独立版 | `sw/app/game_snake/main.c` (462 行) |
| 模式 | 文本模式 VGA |
| CLI 命令 | `snake` |
| IR 快捷键 | Button 5 |

**功能**：
- 3 级难度（Easy/Norm/Hard），速度递增曲线
- 78×27 网格，CP437 box-drawing 边框
- 随机食物放置，碰撞检测
- 实时分数显示，Game Over 画面

**操作**：
- V2 de2shell: 方向键控制，`1/2/3` 选难度
- V3 de2os: PS/2 键盘方向键，`1/2/3` 选难度
- ESC 退出回 shell

**SDRAM 适配**：V3 (de2shell_rtos) 下 snake_x/snake_y 数组用 `__attribute__((section(".sdram_bss")))` 放到 SDRAM，避免 DMEM 不足。

---

### 2. Conway's Game of Life（康威生命游戏）

**两种实现：纯软件版 + FPGA 硬件加速版。**

#### 2a. 软件版

| 属性 | 值 |
|------|-----|
| 文件 | `sw/app/de2shell/life.c` (277 行) |
| 独立版 | `sw/app/game_life/main.c` (329 行) |
| 模式 | 文本模式 VGA |
| CLI 命令 | `conwaylife` 或 `life` |
| IR 快捷键 | Button 6 |

**功能**：
- 40×20 网格，环形边界（上下左右连通）
- 内置经典图案：Glider、Gosper Glider Gun、R-pentomino、Acorn、Pulsar、Blinker
- 随机填充、清除、单步、自动运行
- 编辑模式：鼠标/键盘点选活细胞
- 世代计数器，速度可调

**操作**：
- `R` 随机、`C` 清除、`N` 单步、`Space` 暂停/继续
- `1-6` 加载预设图案
- 编辑模式：方向键移动光标，`Space` 切换细胞
- ESC 退出

#### 2b. 硬件加速版

| 属性 | 值 |
|------|-----|
| 文件 | `sw/app/de2shell/conway_hw.c` (237 行) |
| VHDL 引擎 | `src/rtl/periph/conway_engine.vhd` |
| 模式 | FPGA 引擎计算，CPU 读结果渲染 |
| 地址 | 0xF0012000 (wb_intercon s10) |

**VHDL 引擎**：
- 32×80 网格，硬件并行计算下一代
- MMIO 寄存器：cmd（clear/random/step/auto）、status（busy/generation）、population、grid_row
- CPU 逐行读取 80-bit row data 渲染到 VGA

**与软件版差异**：网格尺寸 32×80（更大），计算由 FPGA 完成（更快），保留编辑和预设图案功能。

---

### 3. PONG

**两种实现：软件控制器版 + FPGA 硬件引擎版。**

#### 3a. 软件版（控制器 only）

| 属性 | 值 |
|------|-----|
| 文件 | `sw/app/de2shell/pong_game.c` (95 行) |
| 模式 | 文本模式 VGA（仅显示挡板位置条） |
| 地址 | 0xF0011000 (寄存器写入) |

**功能**：极简版 — 只画一个 20 格的挡板位置指示条，实际渲染依赖硬件引擎。写入 paddle_y 到 0xF0011000，写入 serve 到 0xF001100C。

**操作**：W/S 移挡板，ENTER 发球，ESC 退出。

#### 3b. 硬件版

| 属性 | 值 |
|------|-----|
| 文件 | `sw/app/de2shell/pong_hw.c` (170 行) |
| VHDL 引擎 | `src/rtl/periph/pong_engine.vhd` |
| 模式 | FPGA 接管 VGA，完整物理+渲染 |
| 地址 | 0xF0011000 (wb_intercon s9) |

**VHDL 引擎**：
- FPGA 内部处理球物理、碰撞检测、分数、VGA 渲染
- CPU 只写 paddle 位置和 control 命令

**MMIO 寄存器**：
| 偏移 | 读写 | 功能 |
|------|------|------|
| 0x00 | W | paddle_l: 左挡板 Y 坐标 [9:0] |
| 0x04 | W | paddle_r: 右挡板 Y 坐标 [9:0] |
| 0x08 | W | control: bit0=serve, bit1=pause, bit2=enable |
| 0x0C | R | scores: [15:8]=left, [7:0]=right |

**操作**：
- 左挡板: W/S
- 右挡板: Up/Down 或 I/K
- Space 发球，P 暂停，Q 退出

**状态**：VHDL 引擎和 Wishbone 接线已完成，board verify 待做。

---

### 4. ChromaShader（程序化地形沙盒）

| 属性 | 值 |
|------|-----|
| 文件 | `sw/app/de2shell_rtos/chroma.c` (443 行) |
| 模式 | 文本模式 VGA（ANSI 24-bit 色彩） |
| 固件 | 仅 de2shell_rtos (V3) |
| 规格文档 | `doc/chromashader-spec.md` |

**功能**：
- 40×25 程序化地形世界（深水、浅水、沙滩、草地、森林、山岩、雪峰 7 种生物群系）
- Perlin-like 哈希地形生成，每次运行不同地图
- 玩家 `[ ]` 移动探索，收集金矿 `♦`
- 收集 10 个金矿获胜
- CP437 半块字符模拟像素级地形纹理

**操作**：WASD 移动，R 重新生成地图，Q 退出。

---

## 独立版本（不依赖 de2shell/de2os）

| 游戏 | 文件 | 行数 | 输出 | 说明 |
|------|------|------|------|------|
| Snake | `sw/app/game_snake/main.c` | 462 | UART | 完整实现，I/O 抽象层 |
| Game of Life | `sw/app/game_life/main.c` | 329 | UART | 完整实现，I/O 抽象层 |
| PS2 test | `sw/app/ps2_test/main.c` | — | UART | PS2 scancode 转储工具 |
| IR test | `sw/app/ir_test/main.c` | — | UART | NEC IR 解码测试 |

独立版通过 `#ifdef LOCAL_BUILD` 支持 PC 编译（SDL2/GCC），`#else` 走 NEORV32 UART。

---

## 游戏 CLI 注册方式

### V2 de2shell（裸机）
`sw/app/de2shell/main.c` 中 `enter_program()` 跳转到 `program_t` 回调结构体：

```c
const program_t prog_snake = {
    "SNAKE", "SNAKE — 方向键=移动 ESC=退出",
    init, update, input, NULL, finish
};
```

shell 解析 `snake`/`conwaylife` 等命令后调用 `enter_program(PROG_SNAKE)`。

### V3 de2shell_rtos（FreeRTOS）
`sw/app/de2shell_rtos/main.c` 注册 FreeRTOS+CLI 命令：

```c
static const CLI_Command_Definition_t cmd_snake_def =
    {"snake", "snake:    Snake game\r\n", cli_snake, 0};
```

---

## 硬件引擎地址汇总

| 引擎 | 地址 | wb_intercon | 状态 |
|------|------|-------------|------|
| pong_engine | 0xF0011000 | s9 | VHDL+C 完成，board verify 待做 |
| conway_engine | 0xF0012000 | s10 | VHDL+C 完成，board verify 待做 |

---

## 未实现 / 规划中

| 项目 | 状态 | 说明 |
|------|------|------|
| 超级马里奥 | 已否决 | 50MHz CPU 无法支撑像素级平台跳跃 + 卷轴 |
| 音效/BGM | 未开始 | DDS 0xF000D000 地址已预留，未接线 |
| Win 3.0 桌面 GUI | V3P5 规划 | `gfx.c`/`gui.c`/`fb_hal.c` 存在，仅 SDL2 可编译 |
| 更多文本模式游戏 | 开放 | 欢迎提交，参考 `program_t` 回调架构 |
