# V3: SDRAM 执行 + 图形化 + 硬件加速器 + 密码学可视化

> 日期: 2026-05-24 | 状态: Planning
> 前提: Phase 1-3 (V2) 已完成或接近完成
> 合并: 原 Phase 4 (硬件加速器 + 音频) 并入 V3
> 参考: 多核研究储备 -> `extra-multicore.md` (最低优先级，不纳入计划)
> 归档: V1 -> `archive/implementation_plan-v1-sof-rtos-gui.md`, V2 -> `archive/implementation_plan-v2-vga-terminal.md`

> **注意**: Phase 1-3 (V2) 仍在实现中，SDRAM 执行调试由另一实例负责。本文档为后续规划，不阻塞当前 V2 工作。

> **V2 -> V3 切换流程**: 当 V2 完成并准备进入 V3 时，将当前 `doc/phases/phase1-3` 归档到 `doc/archived/v2_phase/`，然后在 `doc/phases/` 中给出 V3 的执行规划。当前阶段不要操作，等实际切换时再执行。

---

## 本阶段概述

解除 64KB IMEM 瓶颈，启用 SDRAM 执行，引入 FreeRTOS 多任务和自定义图形层，加入 FPGA 硬件加速器和音频，最终目标是**密码学 RISC-V 指令数据流的可视化演示**。

---

## V2 -> V3 完整对照

| | **V2** (当前) | **V3** (本阶段) |
|---|---|---|
| **代码执行** | 64KB IMEM 直接执行 (boot mode 2) | IMEM 仅 ~2KB bootloader，主程序 SDRAM 执行 (boot mode 0) |
| **代码空间** | 64KB 硬上限 | 128MB (SDRAM) |
| **操作系统** | 裸机轮询 | **FreeRTOS**（crypto/gui/input 三任务） |
| **VGA 显示** | 80x25 256色文本终端 (RGB332 前景/背景) | 文本模式保留 + **640x480 256色像素帧缓冲**双模式 |
| **图形** | 无（纯文字输出） | **自定义图元库**（fill_rect/draw_line/draw_text/bitblt） |
| **PC 仿真** | `make local` 只能跑逻辑 | **SDL2 帧缓冲仿真**，PC 上实时预览图形 |
| **视觉风格** | 终端文字（绿底黑字 Norton Commander 风） | Win 3.0 色调 + Exp7 渐变壁纸 |
| **密码学** | UART 文本输出 + de2shell 子命令 | **图形化可视化**：AES/SHA 框图 + 箭头 + 高亮 + 实时数据 |
| **输入** | PS/2 键盘 + IR 遥控 | 同 V2 |
| **硬件加速器** | 无 | **Conway** + **PONG** + **NTT 加速器** + **ChromaShader 沙盒** |
| **音频** | 无 | **WM8731 I2C/I2S 音频输出** (正弦波测试) |
| **双核** | 无 | **可选 demo**（最低优先级，V3 其余部分稳定后考虑） |
| **答辩演示** | de2shell 命令行操作 + LCD 状态 + VGA 文字 | 密码学可视化 + 硬件加速器 + 彩色终端沙盒 |

**一句话**: V2 证明了能做出来，V3 让它好看且有用。

---

## 1. SDRAM 执行 + Bootloader

### 目标

CPU 主程序从 SDRAM 取指令，IMEM 仅保留一个小 bootloader。

### 硬件改动

| 文件 | 改动 |
|------|------|
| `neorv32_wrapper.vhd` | `ICACHE_EN => true`, `BOOT_MODE => 0` (bootloader) |
| 链接脚本 | `.text` 指向 `0x01000000`（SDRAM 起始） |
| 新增 `bootloader.S` | IMEM 内：初始化 SDRAM -> 拷贝固件 -> 跳转 |

### Bootloader 流程

```
1. 初始化栈指针
2. 拷贝固件：从 flash/UART -> SDRAM 0x01000000
3. 刷新 ICACHE
4. 跳转到 SDRAM 入口
```

### 交付验证

- 简单 `hello` 程序从 SDRAM 执行，UART 输出正常
- `sdram_test` 从 SDRAM 运行仍然 ALL PASS

---

## 2. VGA 像素帧缓冲模式

### 目标

在现有 256色文本终端基础上，新增像素模式——VGA 控制器从 SDRAM 线性读取帧缓冲。

### 双模式设计

| 模式 | 显存来源 | 内容 | 切换方式 |
|------|----------|------|----------|
| Text (现有) | M9K 字符 RAM | ASCII + RGB332 属性 | 默认 |
| Pixel (新增) | SDRAM 帧缓冲 | 640x480x8bpp 线性像素 | 寄存器切换 |

### 帧缓冲参数

- 分辨率: 640x480 @ 60Hz
- 色深: 8bpp（256 色调色板索引）
- 大小: 640 x 480 = 307,200 bytes (~300KB)
- 基地址: 可配置寄存器（默认 0x01000000 + offset）

### 硬件改动

| 文件 | 改动 |
|------|------|
| `vga_text_terminal.vhd` | 加 pixel mode：SDRAM 帧缓冲读 + 模式寄存器 |
| `wb_intercon.vhd` | VGA 需要额外 SDRAM 读取端口（仲裁或共享） |

### VGA 帧缓冲读取的 SDRAM 仲裁

VGA 控制器需要持续读取帧缓冲（~25MB/s @ 640x480x8bppx60Hz）。方案：

1. **CPU 优先 + VGA 窃取空闲周期**: SDRAM 控制器加第二个 master 端口
2. **行缓冲**: VGA 用 M9K 缓存一行像素，减少 SDRAM 读取频率

### 交付验证

- Pixel mode 显示 Exp7 风格 RGB 渐变
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
#define FRAMEBUFFER_BASE 0x01000000  // SDRAM 偏移

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

### FreeRTOS 配置

- 内核: FreeRTOS V11.x
- Tick 来源: CLINT MTIMER (NEORV32 内置)
- 堆: SDRAM (configTOTAL_HEAP_SIZE = 4MB)
- 临界区: `csrwi mie, 0` / `csrwi mie, MIE_MEXT`

### 任务划分

| 任务 | 优先级 | 职责 |
|------|--------|------|
| `t_gui` | 最高 (3) | 从队列读状态，更新帧缓冲 |
| `t_crypto` | 中 (2) | 执行 AES/SHA，每步推状态到队列 |
| `t_input` | 低 (1) | PS/2 / IR 事件读取与分发 |

### 任务间通信

```
t_crypto --[xQueue: crypto_state_t]--> t_gui

typedef struct {
    uint8_t stage;       // 当前流水线阶段
    uint8_t round;       // 当前轮次
    uint8_t state[16];   // 128-bit 中间状态
    uint32_t cycles;     // 已消耗周期数
} crypto_state_t;
```

### 交付验证

- 三个任务同时运行，crypto 不卡 GUI
- PS/2 按键可切换演示模式

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

纯硬件 B3/S23 计算 + 双缓冲 VGA 输出。CPU 只做初始化图案和暂停/继续控制。

```
+----------+     +--------------+     +----------+
| 当前网格  | --> | 邻居计数+规则 | --> | 下一网格  |
| BRAM A   |     | 8读 1写流水线 |     | BRAM B   |
+----------+     +--------------+     +----------+
       ^              |                     |
       +---- 交换 ----+                     v
                                       VGA 像素映射
```

### 规格

| 参数 | 值 |
|---|---|
| 网格 | 80x25 (匹配 VGA 字符终端) 或更高分辨率 (像素模式) |
| 规则 | B3/S23, 环面边界 |
| @50MHz | ~20 ns/代 — 每秒 5000 万代 |
| 资源估算 | ~500 LEs, 0 DSP, 1 M9K |

### 寄存器接口 (0xF000F000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x00 | W | 命令: 0=clear, 1=glider, 2=gun, 3=random |
| 0x04 | R/W | 控制: bit0=enable, bit1=pause, bit2=single_step |
| 0x08 | R | 代数计数器 [31:0] |

### 交付验证

- IR 遥控器切换 Conway 频道，VGA 实时显示演化
- 5000 万代/秒，肉眼看到瞬间填满屏幕

---

## 8. PONG 硬件引擎

> 从原 Phase 4 移入。

### 设计

经典双人 PONG，纯硬件 VGA 渲染，零 BRAM。球位置存寄存器，非帧缓冲。

### 规格

| 参数 | 值 |
|---|---|
| 分辨率 | 640x480 像素区域 |
| 球 | 8x8 像素方块, 硬件碰撞检测 |
| 球拍 | 8x40 像素, PS/2 键盘控制 |
| 物理 | 反弹角取决于击球位置 |
| 资源估算 | ~800 LEs, 0 DSP, 0 M9K |

### 寄存器接口 (0xF000E000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x00 | W | 左球拍位置 [8:0] (PS/2 W/S) |
| 0x04 | W | 右球拍位置 [8:0] (PS/2 Up/Down) |
| 0x08 | R | 得分: [15:8]=左, [7:0]=右 |
| 0x0C | W | 控制: bit0=reset, bit1=pause |

### 交付验证

- 双人 PS/2 键盘对战，VGA 实时渲染，流畅 60fps

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

### 寄存器接口 (0xF000C000)

| 偏移 | R/W | 说明 |
|---|---|---|
| 0x000-0x3FF | R/W | 数据缓冲 [0..255]，word-indexed by adr[9:2]，12-bit |
| 0x400 | W | 控制: bit0=start, bit1=dir (0=NTT, 1=INTT) |
| 0x404 | R | 状态: bit0=busy, bit1=done (sticky, clear on start) |
| 0x408 | R | 周期数计数器 [31:0] |

### 实现状态 (2026-05-24)

- ☑ `ntt_sdf.vhd` — DIF Cooley-Tukey, stages 7→0, 统一蝶形 (A+B, (A-B)*w)
- ☑ Python 验证 `ntt_verify.py` 全部 PASS (round-trip / delta / convolution / vs naive)
- ☑ Wishbone 集成: wb_intercon s4 + de2_115_top 实例化, 基地址 0xF000C000
- ☑ C 驱动 `ntt.c` + `ntt.h` — SW reference (LOCAL_BUILD) + HW MMIO driver (NEORV32)
- ☑ 软件算法验证: delta / round-trip (range + random) / convolution 全 PASS
- ⬜ Quartus 编译验证
- ⬜ de2shell 接入 `ntt` 命令 (驱动已完成，接入待 Phase 3 收尾)

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

## 11. 音频子系统

> 从原 Phase 4 移入。纯锦上添花。

### 硬件架构

```
CPU (NEORV32)                    DE2-115 板载
+----------+                     +-----------------+
| de2shell |-- XBUS --> WM8731   | WM8731 CODEC    |
| audio.c  |          registers  | +- I2C (配置)   | -> LINE_OUT
|          |-- XBUS --> I2S TX   | +- I2S (数据)   | -> HEADPHONE
+----------+                     | +- MCLK (18.432)|
                                 +-----------------+
```

### 模块

| 模块 | 资源估算 | 说明 |
|---|---|---|
| `wm8731_ctrl.vhd` | ~200 LEs | I2C 主机 + WM8731 寄存器初始化 |
| `i2s_tx.vhd` | ~100 LEs | 16-bit 立体声 I2S 发送 |

### 交付验证

- `tone` 命令从 LINE_OUT 播放 440Hz 正弦波

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

| 模块 | LEs | DSP | M9K | 来源 |
|---|---|---|---|---|
| V2 已有 | ~8,344 | 8 | 30 | 已编译 |
| VGA 像素帧缓冲 | ~200 | 0 | 2 | 新增 |
| Conway 硬件引擎 | ~500 | 0 | 1 | 新增 |
| PONG 硬件引擎 | ~800 | 0 | 0 | 新增 |
| NTT 加速器 | ~2,000 | ~64 | ~4 | 新增 |
| ChromaShader | ~280 | 0 | 8 | 新增 |
| 音频 (I2C + I2S) | ~300 | 0 | 0 | 新增 |
| 双核增量 (可选) | ~4,000 | ~8 | ~16 | 可选 |
| **V3 合计 (不含双核)** | **~12,424** | **~72** | **~45** | — |
| 板载资源 | 114,480 | 532 | 432 | — |
| 占用率 | **10.9%** | **13.5%** | **10.4%** | 极度充裕 |

---

## 优先级与时间估算

| 优先级 | 子任务 | 估算时间 | 依赖 |
|--------|--------|----------|------|
| **P0** | 1. SDRAM 执行 + bootloader | 4h | V2 完成 |
| **P0** | 3. VGA HAL + SDL2 仿真 | 3h | 无（可立即开始） |
| **P1** | 5. FreeRTOS 移植 | 4h | SDRAM 执行 |
| **P1** | 2+4. 图元库 + VGA 像素模式 | 5h | SDL2 HAL |
| **P2** | 6. 密码学可视化 (AES+SHA) | 6h | 图元库 + FreeRTOS |
| **P2** | 7. Conway 硬件引擎 | 4h | 独立 |
| **P2** | 10. ChromaShader 沙盒 | 6h | 独立 (需改造 VGA 数据源) |
| **P2** | 8. PONG 硬件引擎 | 4h | 独立 |
| **P3** | 9. NTT 加速器 | 8h | 复用 FFT 项目 |
| **P3** | 11. 音频 I2C + I2S | 3h | 独立 |
| **P4** | 12. 双核 SMP demo | 0.5-4h | V3 全部完成 + 有余力 |
| **总计 (P0-P3)** | | **~47h** | |

---

## 不做的事

| 项目 | 原因 |
|------|------|
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
| [Graphite](https://github.com/danodus/graphite) | SDL2 仿真方案 + 2D 加速器参考 |
| [NekoIchi](https://github.com/ecilasun/NekoIchi) | 命令队列式 GPU 参考 |
| NEORV32 ICACHE 文档 | SDRAM 执行配置 |
| FreeRTOS RISC-V 移植指南 | 任务调度实现 |
| FFT SDF 架构 | NTT 加速器设计基础 |
| Terasic DE2-115 CDROM | I2C/I2S 参考代码 |
| ChromaShader 规格书 | 沙盒世界设计参考 (FPGA-SANDBOX-SPEC-001) |
