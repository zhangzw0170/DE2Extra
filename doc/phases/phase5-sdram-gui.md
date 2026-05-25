# V3: SDRAM 执行 + 图形化 + 硬件加速器 + 密码学可视化

> **SUPERSEDED**: This document is the original V3 master plan. It has been superseded by the v3px.md series for active planning. Addresses and port assignments in this file may be outdated — see `de2extra_pkg.vhd` and `wb_intercon.vhd` for the current address map.

> 日期: 2026-05-25 (最近更新) | 状态: Active (V2 complete, V3 in progress)
> 前提: V2 (v0.1) 验收完成 — de2shell frozen
> 合并: 原 Phase 4 (硬件加速器 + 音频) 并入 V3
> 参考: 多核研究储备 -> `extra-multicore.md` (最低优先级，不纳入计划)
> 归档: V1 -> `archive/implementation_plan-v1-sof-rtos-gui.md`, V2 -> `archive/implementation_plan-v2-vga-terminal.md`

> **关键设计决策**: de2shell (bare-metal, IMEM 64KB) 冻结在 V2。V3 所有工作在 **de2os** 上进行（`sw/app/de2shell_rtos/` + `par/de2os/`）。Shell 接收 PS/2 键盘输入作为主输入源（UART 辅助）。不再更新 de2shell。
>
> **Conway/PONG 接入策略**: VHDL 和 C 驱动已完成，但暂不接入 de2os_top/QSF — 等 VGA + RTOS 稳定后再集成。当前 de2os_top 中 s9/s10 信号 stub (immediate ACK, zero data)。

---

## 本阶段概述

解除 64KB IMEM 瓶颈，启用 SDRAM 执行，引入 FreeRTOS 多任务和自定义图形层，加入 FPGA 硬件加速器和音频，最终目标是**密码学 RISC-V 指令数据流的可视化演示**。

---

## V2 -> V3 完整对照

| | **V2** (当前) | **V3** (本阶段) |
|---|---|---|
| **代码执行** | 64KB IMEM 直接执行 (boot mode 2) | IMEM 仅 ~2KB bootloader，主程序 SDRAM 执行 (boot mode 0) |
| **代码空间** | 64KB 硬上限 | 128MB (SDRAM) |
| **操作系统** | 裸机轮询 | **FreeRTOS V11.3.0**（4 任务: input/shell/active/status） |
| **VGA 显示** | 80x25 256色文本终端 (RGB332 前景/背景) | 文本模式保留 + **640x480 256色像素帧缓冲**双模式 |
| **图形** | 无（纯文字输出） | **自定义图元库**（fill_rect/draw_line/draw_text/bitblt） |
| **PC 仿真** | `make local` 只能跑逻辑 | **SDL2 帧缓冲仿真**，PC 上实时预览图形 |
| **视觉风格** | 终端文字（绿底黑字 Norton Commander 风） | Win 3.0 色调 + Exp7 渐变壁纸 |
| **密码学** | UART 文本输出 + de2shell 子命令 | **图形化可视化**：AES/SHA 框图 + 箭头 + 高亮 + 实时数据 |
| **输入** | PS/2 键盘 + IR 遥控 | **PS/2 键盘主输入** (UART 辅助) + IR 遥控 |
| **硬件加速器** | 无 | **Conway** + **PONG** + **NTT 加速器** + **ChromaShader 沙盒** |
| **音频** | 无 | **PS/2 双轨合成器**: 3xOSC 加法合成 + DX7 FM 合成, WM8731 输出 |
| **双核** | 无 | **可选 demo**（最低优先级，V3 其余部分稳定后考虑） |
| **答辩演示** | de2shell 命令行操作 + LCD 状态 + VGA 文字 | 密码学可视化 + 硬件加速器 + 彩色终端沙盒 |

**一句话**: V2 证明了能做出来，V3 让它好看且有用。

---

## 1. SDRAM 执行 + Bootloader

### 目标

CPU 主程序从 SDRAM 取指令，IMEM 仅保留 NEORV32 内置 bootloader。

### 当前状态

☑ 已实现。de2os 独立 Quartus 工程已编译通过 (`par/de2os/de2os.sof`)，de2shell_rtos 固件成功链接到 SDRAM (73KB @ 0x01000000)。

### 实际实现

| 组件 | 文件 | 说明 |
|------|------|------|
| 独立顶层 | `src/rtl/de2os_top.vhd` | 自有 generics: BOOT_MODE=0, ICACHE_EN=true, ICACHE_BURSTS=true |
| 独立 Quartus | `par/de2os/de2os.qpf/qsf` | 精简外设集 (无 expdemo，含 ntt_sdf + vga_pixel_ctrl) |
| 固件构建 | `sw/app/de2shell_rtos/makefile` | `--defsym __neorv32_rom_base=0x01000000` 将 .text 定位到 SDRAM |
| 补充链接脚本 | `sw/app/de2shell_rtos/de2shell_rtos.ld` | framebuffer=0x01800000, FreeRTOS heap=0x01900000 |
| Bootloader | NEORV32 内置 (boot_mode=0) | UART 自动上传固件到 SDRAM 并跳转，无需自定义 bootloader.S |

### 编译结果 (de2os)

- LEs: 8,125 / 114,480 (7%)
- Fmax: 50MHz 域 77.29 MHz, 100MHz 域 151.06 MHz — 无时序违例
- de2os.sof 已生成 (3.4MB)

### 交付验证 (🔌 待上板)

- de2shell_rtos 从 SDRAM 执行，shell 通过 UART/PS/2 可交互
- sdram_test 逻辑在 SDRAM 执行路径下仍然正常

---

## 2. VGA 像素帧缓冲模式

### 目标

在现有 256色文本终端基础上，新增像素模式——VGA 控制器从 SDRAM 线性读取帧缓冲。

### 当前状态

☑ VHDL + 接线完成。`vga_pixel_ctrl.vhd` 已在 de2os_top 中实例化 (`u_vga_px`)，寄存器地址 >= 0x1F80 分流到像素控制器，SDRAM 读端口已连接。3-way VGA MUX 已实现 (PONG > pixel > text)。🔌 待上板。

### 双模式设计

| 模式 | 显存来源 | 内容 | 切换方式 |
|------|----------|------|----------|
| Text (现有) | M9K 字符 RAM | ASCII + RGB332 属性 | 默认 |
| Pixel (新增) | SDRAM 帧缓冲 (0x01800000) | 640x480x8bpp RGB332 线性像素 | 寄存器切换 |

### 帧缓冲参数

- 分辨率: 640x480 @ 60Hz
- 色深: 8bpp RGB332
- 大小: 640 x 480 = 307,200 bytes (~300KB)
- 基地址: **0x01800000** (由链接脚本 `__de2_framebuffer_base` 定义)

### 架构

```
vga_pixel_ctrl (独立实体，非 vga_text_terminal 子模块)
├── 寄存器接口: mode_en, fb_base, status (类似 Wishbone，通过 wb_intercon 地址解码)
├── SDRAM 读取: burst 模式，从 sdram_ctrl 读取帧缓冲数据
├── 双行缓冲: ping-pong line buffer (160 words × 32-bit, M9K)
└── 输出: RGB332 → VGA DAC
```

### 剩余工作

1. ~~在 de2os_top 中将 vga_pixel_ctrl 的寄存器信号接到 wb_intercon~~ ☑ 已完成
2. ~~VGA 输出 MUX：vga_pixel_mode 信号选择 text/pixel 输出到 VGA 引脚~~ ☑ 已完成
3. 软件端 fb_hal.c 已完成，写 0xF0000000+0x1F80 启用像素模式

### 交付验证 (🔌 待上板)

- Pixel mode 显示 RGB 渐变
- Text/Pixel 模式可软件切换

---

## 3. SDL2 仿真 + VGA HAL

### 目标

PC 端无板开发，`make local` 编译后直接在窗口中预览图形输出。

### 架构

```
应用层    crypto_viz.c -- 画流水线框、箭头、高亮
-----------------------------------------------
图元层    gfx_primitives.c -- fill_rect / draw_line / draw_text / bitblt
-----------------------------------------------
HAL 层    vga_hal.c -- #ifdef LOCAL_BUILD: SDL2 / else: SDRAM 帧缓冲写
```

### HAL 接口

```c
// vga_hal.h
#define FB_W 640
#define FB_H 480
#define FB_BPP 8   // 256色

void vga_init(void);       // SDL2: 开窗口 / FPGA: 指向 SDRAM 基址
void vga_set_pixel(int x, int y, uint8_t c);
void vga_present(void);    // SDL2: SDL_RenderPresent / FPGA: no-op
void vga_shutdown(void);   // SDL2: 清理 / FPGA: no-op
```

### FPGA 后端

```c
#define FRAMEBUFFER_BASE 0x01800000  // SDRAM 偏移 (与代码区分离)

static inline void vga_set_pixel(int x, int y, uint8_t c) {
    *(volatile uint8_t*)(FRAMEBUFFER_BASE + y * FB_W + x) = c;
}
```

### SDL2 后端

- 开 640x480 窗口
- 维护 `uint8_t fb[FB_H][FB_W]` 帧缓冲
- 调色板映射：8bpp 索引 -> SDL_Color (RGB332 或自定义 256 色表)
- `vga_present()` 调 `SDL_UpdateTexture` + `SDL_RenderPresent`

### 交付验证

- PC 上 `make local` 运行，显示渐变色填充
- 跨平台编译通过 (Windows/Linux)

### 实现状态 (2026-05-24)

- ☑ `fb_hal.h/c` — 像素帧缓冲 HAL (LOCAL_BUILD=SDL2 / NEORV32=SDRAM) 已完成
- ☑ `fb_test.c` — 冒烟测试通过 (RGB332 渐变 + 窗口图元 + Bresenham 线)
- ☑ `makefile` — `make local` 已集成 SDL2 路径 (via `scoop prefix sdl2`)
- 注: fb_hal 是**像素模式** HAL，与 vga_hal (文本模式) 并存

---

## 4. 自定义图元库

### 图元函数

```c
// gfx_primitives.h
void gfx_fill_rect(int x, int y, int w, int h, uint8_t color);
void gfx_draw_line(int x0, int y0, int x1, int y1, uint8_t color);
void gfx_set_pixel(int x, int y, uint8_t color);
void gfx_draw_char(int x, int y, char c, uint8_t fg, uint8_t bg);
void gfx_draw_text(int x, int y, const char *s, uint8_t fg, uint8_t bg);
void gfx_bitblt(int dst_x, int dst_y, int w, int h, const uint8_t *src, int src_stride);
void gfx_clear(uint8_t color);
```

### 脏区域追踪

```c
void gfx_mark_dirty(int x, int y, int w, int h);
void gfx_flush_dirty(void);
```

- shadow buffer 追踪当前屏幕状态，只写变化的像素

### 视觉风格

- **Win 3.0 色调**: 灰白窗口、深色标题栏、柔和配色
- **Exp7 渐变壁纸**: RGB 渐变背景
- **密码学高亮**: 绿色=活跃指令、橙色=数据流、灰色=待执行

### 交付验证

- PC 上画出一个带标题栏、文字、边框的窗口
- 渐变背景填充

---

## 5. FreeRTOS 移植

### 目标

多任务调度，crypto 计算不阻塞 GUI 渲染。

### 当前状态

☑ 已实现。4 任务运行，固件成功构建 (73KB @ SDRAM)。🔌 待上板验证调度器。

### FreeRTOS 配置

- 内核: FreeRTOS **V11.3.0** (当前使用 V11.1.0+，需更新到最新 release，不追 main)
- Tick 来源: CLINT MTIMER (NEORV32 内置)
- 堆: SDRAM 0x01900000, configTOTAL_HEAP_SIZE = 16KB
- 临界区: `csrwi mie, 0` / `csrwi mie, MIE_MEXT`

### 任务划分 (实际实现)

| 任务 | 优先级 | 栈 | 职责 |
|------|--------|-----|------|
| `t_uart_input` | 3 | 128 words | 轮询 UART + PS/2 MMIO，解码后送入 xInputQueue |
| `t_shell` | 2 | 256 words | 从 xInputQueue 读命令行，解析并启动程序 |
| `t_active` | 2 | 512 words | 当前活跃程序 (动态，由 shell 启动) |
| `t_status` | 1 | 64 words | 状态栏 + 心跳 |

### 任务间通信 (实际)

```
t_uart_input --[xInputQueue: char]--> t_shell/t_active
t_shell --[xProgCmdQueue]--> t_active
t_active -- VGA 输出通过 xVgaMutex 互斥
```

### 预留扩展 (V3 后期)

```
t_crypto --[xQueue: crypto_state_t]--> t_gui  (TODO: 密码学可视化时实现)

typedef struct {
    uint8_t stage;       // 当前流水线阶段
    uint8_t round;       // 当前轮次
    uint8_t state[16];   // 128-bit 中间状态
    uint32_t cycles;     // 已消耗周期数
} crypto_state_t;
```

### 交付验证 (🔌 待上板)

- 四个任务同时运行，shell 可交互
- PS/2 键盘输入到达 shell
- 程序切换正常 (crypto/snake/life/...)

---

## 6. 密码学指令数据流可视化

### 目标

图形化展示 AES/SHA 的内部运算流程，高亮当前执行的 RISC-V 密码学指令。

### AES-128 可视化布局

```
+-- DE2Extra Crypto System --------------------------+
| Demo  Algorithm  Help                             |
+----------------------------------------------------+
|  +-- AES-128 ECB ------------------------------+  |
|  |  Key:  2B7E1516 28AED2A6 ABF71588 09CF4F3C |  |
|  |  Input: 6BC1BEE2 2E409F96 E93D7E11 7393172A|  |
|  |                                             |  |
|  |  +------+  +------+  +------+  +------+   |  |
|  |  |SubByt|->|ShiftR|->|MixCol|->|AddKey|   |  |
|  |  |  []  |  |      |  |      |  |      |   |  |
|  |  +------+  +------+  +------+  +------+   |  |
|  |       Round 3/10    Cycles: 1,240          |  |
|  |  State: A3 2F 6B 4C / 87 E1 D4 9A / ...   |  |
|  +---------------------------------------------+  |
|  [背景: Exp7 RGB 渐变壁纸]                          |
+----------------------------------------------------+
```

### 指令标注

- SubBytes -> `aes32esmi` (Zkne)
- ShiftRows -> 隐含在 `aes32esmi` 中
- MixColumns -> 隐含在 `aes32esmi` 中
- AddRoundKey -> `xor` (标准指令)

### 交付验证

- AES-128 10 轮完整可视化，每步高亮对应流水线阶段
- SHA-256 压缩函数可视化
- 128-bit state 实时更新，性能计数器显示周期数

---

## 7. Conway 生命游戏硬件引擎

> 从原 Phase 4 移入。

### 设计

纯硬件 B3/S23 计算 + 双缓冲 BRAM。CPU 通过 Wishbone 读取网格行并写入 VGA 文本终端显示。

```
+----------+     +--------------+     +----------+
| 当前网格  | --> | 邻居计数+规则 | --> | 下一网格  |
| BRAM A   |     | 1 cell/clock |     | BRAM B   |
+----------+     +--------------+     +----------+
       ^              |                     |
       +---- 交换 ----+                     v
                                       CPU 读取 → VGA 文本终端
```

### 规格

| 参数 | 值 |
|---|---|
| 网格 | 80x25 (匹配 VGA 字符终端) |
| 规则 | B3/S23, 环面边界 (toroidal wrap) |
| 计算速度 | 2000 clocks/代 (@50MHz = 40 μs/代) |
| 随机化 | 16-bit LFSR, ~6.25% 密度 |
| 双缓冲 | M9K ramstyle, buf_sel flip |

### 寄存器接口 (0xF0012000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x00 | W | 命令: bit0=clear, bit1=randomize, bit2=step, bit3=auto_run toggle |
| 0x04 | W | 控制: bits[15:8]=row_index (用于 grid_row 读取), bits[7:0]=seed |
| 0x08 | R | 状态: bit0=busy, bit1=auto_run, bits[17:2]=generation[15:0] |
| 0x0C | R | 人口计数 [15:0] |
| 0x10 | R | grid_row: 32-bit 行数据 bits[31:0] (列 0-31) |

### 实现状态

- ☑ `conway_engine.vhd` -- 完整 VHDL，Wishbone slave 接口
- ☑ `conway_hw.c` -- C 驱动，读取 MMIO 网格行并写入 VGA
- ☑ wb_intercon s10 地址解码 (0xF0012000)
- ☑ de2extra_pkg.vhd ADDR_CONWAY_BASE
- ⬜ **暂未接入 de2os**: VHDL 未加入 QSF，de2os_top 中 s10 stub

### 交付验证 (⬜ 接入后)

- CPU 写 cmd 触发 step/auto_run
- 读取 grid_row 显示到 VGA 文本终端

---

## 8. PONG 硬件引擎

> 从原 Phase 4 移入。

### 设计

经典双人 PONG，纯硬件 VGA 渲染（自含 25MHz 像素时钟 + 640x480 时序），CPU 仅通过 Wishbone 控制球拍位置。

```
CPU (PS/2/UART) → paddle_l/r 寄存器 → PONG 物理引擎 → VGA 像素直接输出
                                              ↕
                                        scores 寄存器 ← CPU 读取
```

### 规格

| 参数 | 值 |
|---|---|
| 分辨率 | 640x480 @ 60Hz |
| 球 | 8x8 像素方块, 硬件碰撞检测 |
| 球拍 | 8x40 像素, CPU 设置位置 |
| 物理 | 墙壁反弹, 球拍碰撞, 出界得分 |
| 资源 | 0 BRAM, 纯寄存器 + 组合逻辑 |
| 像素时钟 | 内部 50MHz→25MHz 分频, 非外部 PLL |

### 寄存器接口 (0xF0011000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x00 | W | 左球拍: bits[9:0] = top Y (0..439) |
| 0x04 | W | 右球拍: bits[9:0] = top Y |
| 0x08 | W | 控制: bit0=serve/reset, bit1=pause, bit2=enable |
| 0x0C | R | 得分: [15:8]=left, [7:0]=right |

### VGA 输出

- `vga_en_o`: '1' 时 PONG 接管 VGA 输出，top-level MUX 优先级最高
- 颜色: 球=黄色, 左拍=青色, 右拍=品红, 中心线=灰色, 边界=白色, 背景=深蓝

### 实现状态

- ☑ `pong_engine.vhd` — 完整 VHDL，自含 VGA + Wishbone slave
- ☑ `pong_hw.c` — C 驱动，PS/2 (W/S + 方向键) + UART (W/S/I/K) 控制
- ☑ wb_intercon s9 地址解码 (0xF0011000)
- ☑ de2extra_pkg.vhd ADDR_PONG_BASE
- ☑ de2os_top.vhd 3-way VGA MUX (PONG > pixel > text)
- ⬜ **暂未接入 de2os**: VHDL 未加入 QSF，de2os_top 中 s9 stub

### 交付验证 (⬜ 接入后)

- 双人 PS/2 键盘对战，VGA 实时渲染 60fps
- UART 备用控制路径正常

---

## 9. NTT 加速器

> 从原 Phase 4 移入。

### 背景

Number Theoretic Transform — FFT 在有限域上的类比，ML-KEM/ML-DSA 等后量子密码标准的核心运算。复用 FFT 项目的 SDF 架构。

### 为什么 NTT 在 DE2-115 上特别合适

| 特性 | FFT | NTT |
|---|---|---|
| 数据类型 | float32 或 Q3.12 | **12-bit 整数** |
| 复数乘 | 4 DSP / 1 DSP48E1 | **1 个 18x18 DSP** |
| 精度 | 每级累积误差 | **精确 (有限域)** |

### 规格

| 参数 | 值 |
|---|---|
| 模数 | q = 3329 (ML-KEM-512, 12-bit 素数) |
| 点数 | 128 或 256 |
| 蝶形运算 | (a+b, (a-b) * w mod q) |
| 模乘 | 12x12 -> Barrett reduction -> 12-bit |
| 资源估算 | ~2,000 LEs, ~64 DSP, ~4 M9K |

### 寄存器接口 (0xF000F000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x000-0x3FF | R/W | 数据缓冲 [0..255]，word-indexed by adr[9:2]，12-bit |
| 0x400 | W | 控制: bit0=start, bit1=dir (0=NTT, 1=INTT) |
| 0x404 | R | 状态: bit0=busy, bit1=done (sticky, clear on start) |
| 0x408 | R | 周期数计数器 [31:0] |

### 实现状态 (2026-05-25)

- ☑ `ntt_sdf.vhd` — DIF Cooley-Tukey, stages 7→0, 统一蝶形 (A+B, (A-B)*w)
- ☑ Python 验证 `ntt_verify.py` 全部 PASS (round-trip / delta / convolution / vs naive)
- ☑ Wishbone 集成: wb_intercon s4, 基地址 0xF000F000
- ☑ C 驱动 `ntt.c` + `ntt.h` — SW reference (LOCAL_BUILD) + HW MMIO driver (NEORV32)
- ☑ 软件算法验证: delta / round-trip (range + random) / convolution 全 PASS
- ☑ Quartus 编译通过 — de2os.qsf 包含 ntt_sdf.vhd，编译无错 (de2os: 8,125 LEs)
- ⬜ de2shell_rtos 接入 `ntt` 命令 (驱动已完成，接入 de2shell_rtos makefile)

算法细节:
- g=17 (primitive 256th root), Barrett constant=5039, N^{-1}=3316
- INTT: 逆 twiddle (q - g^{128-k}) + N^{-1} 缩放
- 输出为 bit-reversed 顺序，软件负责 bit-reversal

### 交付验证

- NTT/INTT 结果正确，加速比 > 1000x vs 纯 C

---

## 10. ChromaShader — 彩色终端沙盒世界

> DE2Extra 适配版。原方案使用 UART ANSI 输出到主机终端，此处改为 VGA 直显。

### 核心创意

在 80x25 VGA 终端上，利用 FPGA 硬件噪声网络实时并行生成无限大的彩色世界。PS/2 键盘操控，零延迟滚动，颜色即信息。

### 为什么改用 VGA 而非 UART

| | UART ANSI (原方案) | VGA 直显 (DE2Extra) |
|---|---|---|
| 刷新延迟 | 全屏 0.76s (@921600 baud) | **< 1ms** (BRAM 直读) |
| 颜色 | 24bit 真彩色 | 8bit RGB332 (256色，够用) |
| 输入 | UART 转发键盘 | **PS/2 直连** |
| 独立性 | 需要主机 + 终端软件 | **只需 VGA 显示器** |

### 架构

```
NEORV32 (游戏逻辑/背包/交互)
    |
    | Wishbone
    v
+-- wb_intercon --+-- 噪声网络控制寄存器 (0xF000H000)
|                  |
|                  +-- PS/2 键盘
|
+-- 硬件噪声网络 (时分复用, ~200 LEs)
|      |
|      | 写入
|      v
|   双端口 BRAM (2000x16bit, 4 M9K)
|      |                +-- 改造层 BRAM (可选, 4 M9K)
|      v                v
+-- VGA 文本终端 (数据源切换: 正常/ChromaShader)
```

### 硬件噪声网络

- 时分复用：1 个 LFSR + 坐标散列单元，每周期算 1 格，2000 周期填满全帧
- 2000 周期 @ 50MHz = 40us，远小于帧间隔 (16.7ms)
- 种子 = `hash(world_x, world_y, global_seed)`，改变偏移即改变世界视图

### 地形颜色映射 (RGB332)

```
水域:   BG = 0b000_00_11 (深蓝)
草地:   BG = 0b001_11_01 (绿)
山地:   BG = 0b11_10_00 (棕)
雪峰:   BG = 0b11_11_11 (白)
金矿:   FG = 0b11_11_00 (黄, 叠加在地形上)
围墙:   BG = 0b01_01_01 (灰)
```

### 玩法

- WASD: 滚动世界（改 offset 寄存器，噪声网络 40us 重填）
- E: 采集当前格子资源（读 BRAM 颜色判断类型）
- 1/2/3: 喷涂颜色（写改造层 BRAM）
- C: 打开背包（UART 输出文字状态）
- 胜利条件: 收集 10 个金粒

### 寄存器接口 (0xF000H000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x00 | R/W | 控制: bit0=enable, bit1=trigger_refresh |
| 0x04 | R/W | global_seed [31:0] |
| 0x08 | R/W | offset_x [31:0] |
| 0x0C | R/W | offset_y [31:0] |

### 帧缓存读取 (0xF000I000)

- 软核按地址读取：`addr = (y*80 + x) * 2` -> 读 2 字节 (fg[7:0], bg[7:0])
- 改造层写入：同地址空间，写时优先级高于噪声层

### 资源估算

| 模块 | LEs | M9K |
|---|---|---|
| 噪声生成器 (时分复用) | ~200 | 0 |
| 帧缓存 BRAM | 0 | 4 |
| 改造层 BRAM (可选) | 0 | 4 |
| 控制寄存器 + MUX | ~80 | 0 |
| **合计** | **~280** | **8** |

### 交付验证

- WASD 零延迟滚动，世界颜色连续变化
- E 采集当前地形资源，UART 显示背包
- 喷涂颜色后地形改变
- IR 遥控切换频道 (ChromaShader <-> Conway <-> 正常终端)

---

## 11. 音频子系统 — 双轨合成器 (3xOSC + DX7)

> 从原 Phase 4 移入。PS/2 键盘双轨演奏，左声道 + 右声道独立合成。
> 地址复用: 0xF0013000 (原 "DDS reserved"，现为 DDS 合成器)。

### 目标

PS/2 键盘当钢琴弹：主键盘区（左手）= Track 1 → 左声道，数字小键盘区（右手）= Track 2 → 右声道。两种合成模式可切换。

### 硬件架构

```
PS/2 键盘
├── 主键盘区 (Q-P / A-L / Z-M) ──→ Track 1 (左声道)
│   ┌─────────────────────────────────┐
│   │ 3xOSC 模式:                      │
│   │   OSC1 (基频) + OSC2 (偏移八度)  │
│   │   + OSC3 (偏移八度) → 混音       │
│   │                                   │
│   │ DX7 模式:                        │
│   │   Carrier: sin(φ_c + index ×     │
│   │     sin(φ_m × ratio))           │
│   └──────────────┬──────────────────┘
│                  ↓
├── 数字小键盘区 ──→ Track 2 (右声道) ← 独立合成引擎
│                  ↓
├──────────── 混音器 (L + R) ──────────┤
                  ↓
           I2S 发送器 (48kHz 16-bit stereo)
                  ↓
           WM8731 DAC → LINE_OUT / 耳机
```

### 合成模式

| 模式 | 原理 | 效果 | 复杂度 |
|------|------|------|--------|
| **3xOSC** (加法合成) | 3 个 DDS 振荡器叠加 | 丰富音色，类似 FL Studio 3xOSC | 低 |
| **DX7** (FM 合成) | 调制器正弦波调制载波频率 | 金属感/电子音，经典 Yamaha DX7 | 中 |

#### 3xOSC 模式细节

每个 Track 独立的 3 个振荡器:
- **OSC1**: 基础音高 (按键决定)
- **OSC2**: 八度偏移 (±2 octaves) + 微调 (detune, ±100 cents)
- **OSC3**: 八度偏移 + 微调
- 每个振荡器: 波形选择 (sine/square/saw/triangle) + 独立音量
- 输出 = OSC1×vol1 + OSC2×vol2 + OSC3×vol3

#### DX7 FM 模式细节

每个 Track:
- **Carrier**: sin(φ_c + modulation_index × sin(φ_m))
- **Modulator**: 独立频率比 (ratio: 0.5/1/2/3/4)
- **Modulation index**: 0~127 (0=纯 sine, 127=强烈 FM 泛音)
- 本质是几个加法器 + 一个正弦查找表，FPGA 天然适合

### PS/2 键盘映射

```
Track 1 (主键盘区 — 左手):
  ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
  │ Q │ W │ E │ R │ T │ Y │ U │ I │ O │ P │  ← 黑键: C# D#   F# G# A#
  ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
  │ A │ S │ D │ F │ G │ H │ J │ K │ L │ ; │  ← 白键: C  D  E  F  G  A  B  C
  ├───┴───┼───┴───┼───┴───┼───┴───┼───┴───┤
  │  Z   │  X   │  C   │  V   │  B   │  N  │  ← 低八度 (可选)
  └──────┴──────┴──────┴──────┴──────┴─────┘
  Tab = 八度-1, CapsLock = 八度+1

Track 2 (数字小键盘区 — 右手):
  ┌───┬───┬───┬───┐
  │ 7 │ 8 │ 9 │ / │  ← C4 D4 E4 F4
  ├───┼───┼───┼───┤
  │ 4 │ 5 │ 6 │ * │  ← G4 A4 B4 C5
  ├───┼───┼───┼───┤
  │ 1 │ 2 │ 3 │ - │  ← C3 D3 E3 F3
  ├───┼───┼───┼───┤
  │ 0 │ . │Ent│ + │  ← G3 A3 八度+ / -
  └───┴───┴───┴───┘
  NumLock = Track 2 八度切换
```

### 寄存器接口 (0xF0013000)

| 偏移 | R/W | 说明 |
|------|-----|------|
| 0x00 | R/W | 全局控制: bit0=mute, bit1=mode(0=3xOSC,1=DX7), bits[3:2]=master_vol |
| 0x04 | W | Track 1 MIDI 音符 (0=释放, 21~108=C2~C8) |
| 0x08 | W | Track 1 OSC1: bits[1:0]=waveform, bits[3:2]=octave, bits[15:8]=volume |
| 0x0C | W | Track 1 OSC2: bits[1:0]=wave, bits[3:2]=oct_shift, bits[15:8]=vol, bits[23:16]=detune |
| 0x10 | W | Track 1 OSC3: 同 OSC2 |
| 0x14 | W | Track 2 MIDI 音符 |
| 0x18-0x20 | W | Track 2 OSC1/OSC2/OSC3 (同 Track 1 布局) |
| 0x24 | W | DX7 Track1: bits[7:0]=mod_ratio, bits[15:8]=mod_index |
| 0x28 | W | DX7 Track2: 同上 |
| 0x2C | R | 状态: bit0=busy, bit1=wm8731_ready |

### VHDL 模块

| 模块 | 文件 | 资源估算 | 说明 |
|------|------|----------|------|
| WM8731 I2C 控制器 | `wm8731_ctrl.vhd` | ~200 LEs | I2C 主机 + 上电配置序列 |
| I2S 发送器 | `i2s_tx.vhd` | ~150 LEs | 48kHz 16-bit 立体声, 从 FIFO 读数据 |
| DDS 核心 | `dds_core.vhd` | ~50 LEs/个 | 32-bit 相位累加器 + 波表 ROM 查找 |
| 合成器顶层 | `synth_engine.vhd` | ~200 LEs | 双轨 3xOSC/FM 模式切换 + 混音器 |
| 波表 ROM | 内含 | 1 M9K | 256×16bit × 4 波形 (sin/sq/saw/tri) |

### 软件层

| 文件 | 说明 |
|------|------|
| `synth.c` | 合成器 C 驱动: PS/2 扫描码→MIDI 音符, 写 Wishbone 寄存器 |
| 键盘映射表 | scan_code → note_number 查找表 (主键盘 + 数字区) |
| FreeRTOS 任务 | 可选: 独立 `t_synth` 任务轮询 PS/2 并更新音符寄存器 |

### WM8731 引脚 (DE2-115)

| 信号 | 引脚 | 方向 | 说明 |
|------|------|------|------|
| AUD_XCK | PIN_E1 | OUT | 主时钟 (需要 18.432MHz 或分频) |
| AUD_BCLK | PIN_F2 | OUT | I2S 位时钟 (由 WM8731 生成, slave 模式) |
| AUD_DACLRCK | PIN_E3 | IN | I2S 左右声道选择 (slave 模式) |
| AUD_DACDAT | PIN_D1 | OUT | I2S DAC 数据 |
| AUD_ADCDAT | PIN_D2 | IN | ADC 数据 (暂不用) |
| AUD_ADCLRCK | PIN_C2 | IN | ADC LRCK (暂不用) |
| I2C_SCLK | PIN_B7 | OUT | I2C 配置时钟 |
| I2C_SDAT | PIN_A8 | BIDIR | I2C 配置数据 |

### 实现步骤

1. **WM8731 驱动**: I2C 配置 + I2S 发送器，上板播放 440Hz 正弦波测试
2. **单轨 DDS**: 一个振荡器，CPU 写频率寄存器播放不同音高
3. **PS/2 键盘映射**: 扫描码 → MIDI 音符，实时演奏
4. **双轨分轨**: 主键盘 = Track 1, 数字区 = Track 2, 独立 L/R
5. **3xOSC 模式**: 每轨 3 振荡器叠加，八度偏移 + 微调
6. **DX7 FM 模式**: 调制器 + 载波，FM 泛音

### 资源估算

| 模块 | LEs | M9K | DSP |
|------|-----|-----|-----|
| WM8731 I2C + I2S | 350 | 0 | 0 |
| 6× DDS 核心 (3/track) | 300 | 1 | 0 |
| FM 调制 (2 extra osc) | 50 | 0 | 0 |
| 混音 + Wishbone 寄存器 | 200 | 0 | 0 |
| **合计** | **~900** | **~1** | **0** |

### 交付验证

- `synth` 命令启动合成器模式，PS/2 键盘实时演奏
- 3xOSC 模式：多音色叠加可听
- DX7 模式：FM 泛音效果明显
- 双轨同时演奏，左右声道独立

---

## 12. 双核 SMP Demo (可选)

> 最低优先级。V3 其余部分全部完成且有余力时才考虑。

### 方式

`neorv32_wrapper.vhd` 设置 `DUAL_CORE_EN => true`，软件调用 `neorv32_smp_launch()`。

### 已知限制

- 无硬件缓存一致性，软件需手动 `FENCE`
- SDRAM 带宽共享，加速比 < 2x

### 预估耗时

~0.5h (仅 demo) 到 ~4h (完整双核功能)

---

## 全系统资源预算 (V3 完成后)

> 基于 de2os 编译结果 (de2extra 不含 NTT/pixel ctrl，数据不同)

| 模块 | LEs | DSP | M9K | 来源 |
|---|---|---|---|---|
| de2os 当前已编译 | 8,125 | ~8 | ~30 | 已编译 (含 NTT + vga_pixel_ctrl) |
| Conway 硬件引擎 | ~500 | 0 | 1 | 新增 |
| PONG 硬件引擎 | ~800 | 0 | 0 | 新增 |
| ChromaShader | ~280 | 0 | 8 | 新增 |
| 音频合成器 (3xOSC+DX7) | ~900 | 0 | ~1 | 新增 (0xF0013000) |
| 双核增量 (可选) | ~4,000 | ~8 | ~16 | 可选 |
| **V3 合计 (不含双核)** | **~10,605** | **~8** | **~40** | — |
| 板载资源 | 114,480 | 532 | 432 | — |
| 占用率 | **9.3%** | **1.5%** | **9.3%** | 极度充裕 |

---

## 优先级与时间估算

> 最近更新: 2026-05-25，基于代码实际状态审计。
> V3 全部工作在 de2os 上进行（SDRAM exec + FreeRTOS），de2shell 冻结。
> 状态标注: ☑=代码完成, 🔌=待上板验证, ⬜=未开始, ⏸=暂缓.

| 优先级 | 子任务 | 估算 | 实际状态 | 备注 |
|--------|--------|------|----------|------|
| **P0** | 1. SDRAM 执行 + bootloader | ~~4h~~ | ☑ de2os.sof 已编译 (8,125 LEs) | 🔌 上板 |
| **P0** | 3. VGA HAL + SDL2 仿真 | ~~3h~~ | ☑ fb_hal/gfx/gui 全部 LOCAL_BUILD 通过 | 🔌 上板 |
| **P0** | 13. FreeRTOS+CLI 集成 | 2h | ☑ 19 命令, 31/31 测试 pass | 🔌 上板 |
| **P1** | 5. FreeRTOS 移植 | ~~4h~~ | ☑ 4 任务 (uart_input/shell/active/status) | 🔌 上板 |
| **P1** | 2+4. VGA 像素模式 + 图元库 | ~~5h~~ | ☑ vga_pixel_ctrl 已接线, 3-way MUX | 🔌 上板 |
| **P1** | 14. FreeRTOS+IO 集成 | 3h | ⬜ 待评估 | 当前仅 UART+PS/2, 可能不需要 |
| **P2** | 6. 密码学可视化 (AES+SHA) | 4h | ⬜ 未开始 | GUI 控件库基础已就绪 |
| **P2** | 7. Conway 硬件引擎 | 4h | ☑ VHDL+C 完成, 暂未接入 de2os | 接入需加 QSF + 实例化 |
| **P2** | 8. PONG 硬件引擎 | 4h | ☑ VHDL+C 完成, 暂未接入 de2os | 接入需加 QSF + 实例化 |
| **P2** | 10. ChromaShader 沙盒 | 6h | ⏸ 暂缓 | — |
| **P3** | 9. NTT 加速器 | ~~8h~~ | ☑ VHDL+C+Python 验证 | ⬜ 接入 rtos makefile |
| **P2** | 11. 音频合成器 (3xOSC+DX7) | 6h | ⬜ 未开始 | PS/2 双轨, 0xF0013000 |
| **P3** | Snake Game Over | 0.5h | ⬜ 未开始 | 纯软件 |
| **P3** | Exp6/7 画廊 | 1.5h | ⬜ 未开始 | 纯软件 |
| **P4** | 12. 双核 SMP demo | 0.5-4h | ⬜ 最低优先级 | — |

### 未提交变更 (working tree)

以下文件已修改但未 commit (Conway/PONG 相关 + VGA 接线):
- `wb_intercon.vhd` — 新增 s9/s10 端口
- `de2os_top.vhd` — s9/s10 信号声明 + stub + 3-way VGA MUX
- `de2extra_pkg.vhd` — PONG/CONWAY 地址常量
- `conway_engine.vhd` — 完整 VHDL (不在 QSF 中)
- `pong_engine.vhd` — 完整 VHDL (不在 QSF 中)
- `de2os.qsf` — vga_pixel_ctrl 已在 QSF (conway/pong 未加入)
- `main.c` — prog_conway_hw/prog_pong_hw 声明 + 注册
- `makefile` — conway_hw.c/pong_hw.c 已加入 APP_SRC
- `conway_hw.c`, `pong_hw.c` — C 驱动 (新建)

### 13. FreeRTOS+CLI 集成

**前置**: ~~更新 FreeRTOS submodule 从 V11.1.0+ (开发分支) 到 V11.3.0~~ FreeRTOS+CLI 已作为本地文件集成。

**来源**: `FreeRTOS-Plus/Source/FreeRTOS-Plus-CLI/` — `FreeRTOS_CLI.c`, `FreeRTOS_CLI.h`
**许可**: MIT (FreeRTOS)

**实现状态**:
- ☑ `FreeRTOS_CLI.c/h` 已添加到 `sw/app/de2shell_rtos/`
- ☑ 19 个 CLI 命令已注册 (10 程序启动器 + 3 系统状态 + 6 别名)
- ☑ 替代了手写 `strcmp_local()` 命令解析
- ☑ 独立测试套件: `posix_test/` 目录, mock HAL, 31/31 pass
- 🔌 待上板验证

**已接入的程序**: hello, memtest, crypto, ps2, snake, life, info, monitor, demo, win30, conway_hw, pong_hw

### 14. FreeRTOS+IO 集成

**评估**: 当前仅 UART + PS/2 两个输入源，FreeRTOS+IO 引入成本可能不值得。优先级低于 CLI，**待评估**。。

---

## 不做的事

| 项目 | 原因 |
|------|------|
| de2shell 更新 | V2 frozen，所有新功能走 de2os (SDRAM + FreeRTOS) |
| LVGL | 又一套新框架，自定义图元够用 |
| 3D 加速 | 不是本项目核心 |
| A7Pro 移植 | 6/15 后再说 |
| USB Host | 优先级不够 |
| SD 卡 + FAT 文件系统 | 6/15 后再考虑 |
| 多核 VexRiscv + NEORV32 | 工程量巨大，留给长期探索 |

---

## 参考资源

| 资源 | 用途 |
|------|------|
| **[masonparrish/DE2-115-Synthesizer](https://github.com/masonparrish/DE2-115-Synthesizer)** | **音频首选**: 同板 DE2-115 + PS/2 键盘 + WM8731, 多音色 (Verilog) |
| **[gtaylormb/opl3_fpga](https://github.com/gtaylormb/opl3_fpga)** | **DX7 FM 参考**: Yamaha OPL3 逆向工程, bit-true FM 合成器 (399★) |
| [adam-wills/fpgaFM_matrix](https://github.com/adam-wills/fpgaFM_matrix) | FM 合成器重构, ADSR 包络, DDFS 核心 (SystemVerilog) |
| [mochiruntime/fpga-sound-synthesizer](https://github.com/chau-alexandre/fpga-sound-synthesizer) | VHDL 16 复音合成器, Python 生成波表, MIDI 协议 |
| [ts-manuel/DDS-Function-Generator](https://github.com/ts-manuel/DDS-Function-Generator) | 双通道 DDS, AM/FM 调制 (61★) |
| [aaronsgiles/ymfm](https://github.com/aaronsgiles/ymfm/) | Yamaha FM 核心 (C++ 软仿真, 算法参考) |
| [Graphite](https://github.com/danodus/graphite) | SDL2 仿真方案 + 2D 加速器参考 |
| [NekoIchi](https://github.com/ecilasun/NekoIchi) | 命令队列式 GPU 参考 |
| NEORV32 ICACHE 文档 | SDRAM 执行配置 |
| FreeRTOS RISC-V 移植指南 | 任务调度实现 |
| FFT SDF 架构 | NTT 加速器设计基础 |
| Terasic DE2-115 CDROM | I2C/I2S 参考代码 |
| ChromaShader 规格书 | 沙盒世界设计参考 (FPGA-SANDBOX-SPEC-001) |
