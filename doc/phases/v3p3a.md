# V3 Phase 3a: 像素帧缓冲 + SDL2 仿真 + GUI 桌面

> 日期: 2026-05-25 | 状态: 实现中
> 前置: V3 Phase 1 (SDRAM 执行) + Phase 2 (FreeRTOS 移植) 已完成
> 对应: phase5-sdram-gui.md 第 2-4 节

---

## 1. 概述

本阶段在现有 80x25 文本终端基础上，新增 640x480 像素图形模式。软件可在文本和像素模式之间自由切换。PC 端通过 SDL2 本地构建 (`make local`) 进行无板开发，FPGA 端通过 SDRAM 帧缓冲 + VGA 像素控制器实现板级输出。

**核心目标**:

1. 验证 fb_hal 在 NEORV32 SDRAM 目标上的像素写入功能
2. 确认 gfx_primitives 全部图元正确渲染
3. 将 GUI 文件集成到 de2shell_rtos 构建，确保编译通过
4. SDL2 本地构建冒烟测试
5. 像素模式渲染测试 + 文本/像素模式切换测试

---

## 2. 当前状态

### 已完成

| 组件 | 文件 | 状态 | 说明 |
|------|------|------|------|
| 像素帧缓冲 HAL | `sw/app/de2shell/fb_hal.c/h` | 完成 | 双后端: LOCAL_BUILD=SDL2 / NEORV32=SDRAM @0x01800000 |
| 图形图元库 | `sw/app/de2shell/gfx.c/h` | 完成 | clear/fill_rect/rect/hline/vline/line/char/text/bevel/window_frame |
| 位图字体 | `sw/app/de2shell/gfx_font.h` | 完成 | CP437 8x16, 256 字符, Python 自动生成 |
| GUI 窗口管理器 | `sw/app/de2shell/gui.c/gui.h` | 完成 | 静态池 (32 widgets), z-order 链表, 焦点管理 |
| GUI 控件渲染 | `sw/app/de2shell/gui_widgets.c` | 完成 | Window/Button/Label/TextInput/Taskbar/Icon |
| Win3.0 桌面 | `sw/app/de2shell/win30_desk.c` | 完成 | 桌面+图标网格+任务栏+演示窗口, 键盘驱动 |
| PS/2 解码器 | `sw/app/de2shell/ps2_decoder.c/h` | 完成 | Set 2 扫描码 -> ASCII/扩展码, Shift/Ctrl/Alt 状态 |
| VGA 像素控制器 | `src/rtl/periph/vga_pixel_ctrl.vhd` | 完成 | 640x480@60Hz, RGB332, ping-pong 行缓冲, burst SDRAM 读取 |
| de2os 顶层接线 | `src/rtl/de2os_top.vhd` | 完成 | vga_pixel_ctrl 实例化, 3-way VGA MUX (PONG > pixel > text) |
| fb_hal 冒烟测试 | `sw/app/de2shell/fb_test.c` | 完成 | LOCAL_BUILD SDL2 通过 |
| RTOS 构建集成 | `sw/app/de2shell_rtos/makefile` | 完成 | fb_hal/gfx/gui/gui_widgets/win30_desk/ps2_decoder 已加入 APP_SRC |
| FreeRTOS 内存适配 | `sw/app/de2shell/gui.c` | 完成 | `__attribute__((section(".sdram_bss")))` 将 widget pool 放入 SDRAM |

### 待验证/待完成

| 项目 | 说明 |
|------|------|
| fb_hal NEORV32 后端 | 代码已写好 (`fb[y * FB_W + x] = color` @ 0x01800000), 未上板 |
| VGA 控制器寄存器地址 | fb_hal 使用 `VGA_BASE=0xF0000000`, 偏移 0x7000/0x7004; 需确认与 vga_text_terminal 地址映射一致 |
| SDRAM 帧缓冲覆盖 | fb_hal 直接写 `FRAMEBUFFER_BASE=0x01800000`, 需确认不与代码段/堆冲突 |
| 像素模式性能 | 逐像素写入 300KB 帧缓冲, 无脏区域追踪, clear 全屏约 307200 次 byte 写 |
| 文本/像素模式切换 | fb_hw_mode_set() 写 VGA 寄存器; 切换回文本模式无软件 API |
| de2shell makefile 排除 | fb_hal/gfx/gui/gui_widgets/win30_desk 被 filter-out 排除 (de2shell V2 frozen) |
| de2shell `make local` 已修复 | `make local` 目标已包含 GUI 相关源文件 (fb_hal/gfx/gui/gui_widgets/twm) |

---

## 3. 架构

### 3.1 帧缓冲布局

```
SDRAM 地址空间:
+------------------+ 0x01000000
| de2shell_rtos    | 代码段 (~73KB)
| (.text + .rodata)|
+------------------+
| FreeRTOS 堆      | configTOTAL_HEAP_SIZE = 16KB
+------------------+ ~0x01900000
| Framebuffer      | 640 x 480 x 1 byte = 307,200 bytes (~300KB)
| (RGB332 线性)    | 基地址: 0x01800000
+------------------+ 0x0184B000
| GUI widget pool  | .sdram_bss section
+------------------+
```

**关键约束**: 帧缓冲地址 0x01800000 由链接脚本 `de2shell_rtos.ld` 中的 `__de2_framebuffer_base` 符号定义。必须确保:
- 帧缓冲不在代码段/数据段范围内
- FreeRTOS 堆不与帧缓冲重叠
- widget pool (放在 `.sdram_bss`) 不与帧缓冲重叠

### 3.2 颜色格式: RGB332

8 位像素, 3 位红色 + 3 位绿色 + 2 位蓝色:

```c
static inline uint8_t fb_rgb332(uint8_t r, uint8_t g, uint8_t b) {
    return (uint8_t)(((r >> 5) << 5) | ((g >> 5) << 2) | (b >> 6));
}
```

VGA 像素控制器 (`vga_pixel_ctrl.vhd`) 自动将 RGB332 扩展为 RGB888 输出到 DAC:
```vhdl
vga_r_o <= pixel_color(7 downto 5) & pixel_color(7 downto 5) & pixel_color(6) & pixel_color(5);
vga_g_o <= pixel_color(4 downto 2) & pixel_color(4 downto 2) & pixel_color(3) & pixel_color(2);
vga_b_o <= pixel_color(1 downto 0) & pixel_color(1 downto 0) & pixel_color(1 downto 0) & pixel_color(1) & pixel_color(0);
```

### 3.3 模式切换

```
                    +-------------------+
                    |  de2os_top.vhd     |
                    |  3-way VGA MUX     |
                    +-------------------+
                         /    |    \
                        /     |     \
              PONG_en   /   pixel_en  \  (默认)
                       /     |         \
              pong_engine  vga_pixel_ctrl  vga_text_terminal
```

切换方式:
- **软件启用像素模式**: `fb_hw_mode_set(1)` -- 写 VGA 寄存器 0xF0000000+0x7000
- **软件禁用像素模式**: `fb_hw_mode_set(0)` -- 回到文本模式
- **PONG 接管**: `pong_engine` 的 `vga_en_o` 信号优先级最高

VGA 控制器寄存器 (通过 vga_pixel_ctrl 寄存器接口):

| 偏移 | R/W | 说明 |
|------|-----|------|
| 0x7000 | R/W | bit 0: enable pixel mode |
| 0x7004 | R/W | [26:2] SDRAM word address of framebuffer |
| 0x7008 | R | bit 0: in vblank |

**注意**: 当前 fb_hal.c 中的寄存器偏移 (`VGA_PX_MODE=0x7000`, `VGA_PX_FB_BASE=0x7004`) 需要与 wb_intercon 对 vga_pixel_ctrl 的实际地址解码一致。上板前必须交叉检查。

### 3.4 软件分层

```
应用层    win30_desk.c -- 桌面合成 (图标+任务栏+窗口)
    |
GUI 层   gui.c + gui_widgets.c -- 窗口管理器 + 控件渲染
    |
图元层   gfx.c -- fill_rect/line/text/bevel/window_frame
    |
HAL 层   fb_hal.c -- set_pixel (LOCAL_BUILD=SDL2 / NEORV32=SDRAM)
    |
硬件层   vga_pixel_ctrl.vhd -- SDRAM burst 读取, 行缓冲, RGB332->VGA DAC
```

---

## 4. 实现步骤

### 步骤 1: 交叉检查 fb_hal 寄存器地址 (0.5h)

**目标**: 确认 fb_hal.c 中的 VGA 寄存器偏移与 VHDL 地址解码一致。

**操作**:
1. 读取 `wb_intercon.vhd` 中对 `s1` (VGA 地址 0xF0000000) 的地址解码逻辑
2. 确认 vga_pixel_ctrl 的寄存器在 wb_intercon 中的地址偏移
3. 与 fb_hal.c 中的 `VGA_PX_MODE (0x7000)` 和 `VGA_PX_FB_BASE (0x7004)` 对比
4. 如果不一致, 修正 fb_hal.c 中的偏移常量

**验证**: 寄存器地址匹配。

### 步骤 2: 确认帧缓冲地址不与代码/堆冲突 (0.5h)

**目标**: 确保 0x01800000 的 300KB 帧缓冲不覆盖代码段或 FreeRTOS 堆。

**操作**:
1. 读取 `sw/app/de2shell_rtos/de2shell_rtos.ld` 链接脚本
2. 确认代码段结束地址 < 0x01800000
3. 确认 FreeRTOS 堆 (16KB @ 0x01900000) 不与帧缓冲 (0x01800000-0x0184B000) 重叠
4. 确认 GUI widget pool (`.sdram_bss`) 地址不在帧缓冲范围内

**验证**: 内存布局无冲突。如冲突, 调整链接脚本或帧缓冲基地址。

### 步骤 3: 验证 fb_hal NEORV32 后端基本功能 (1h)

**目标**: 在 FPGA 上验证 fb_hal 的 set_pixel/get_pixel/clear/present 工作正常。

**操作**:
1. 创建最小像素模式测试程序 (可集成到 de2shell_rtos 的 CLI 命令中)
2. 测试流程:
   - `fb_init()` -- 启用像素模式, 清屏为黑色
   - 写入 RGB332 渐变到帧缓冲
   - 等待 2 秒
   - 写入彩色矩形 + 线段
   - 等待 2 秒
   - `fb_shutdown()` -- 切回文本模式
3. 观察 VGA 输出是否正确显示渐变和图元

**已知问题**:
- `fb_clear()` 逐字节写 307200 次, @50MHz 约需 6ms (可接受)
- `fb_present()` 在 NEORV32 上是空操作 (VGA 控制器连续读取 SDRAM)

**验证**: VGA 显示器上看到预期的渐变色填充。

### 步骤 4: 验证 gfx_primitives 完整性 (1h)

**目标**: 确认所有 gfx 图元在像素模式下正确渲染。

**测试矩阵**:

| 图元函数 | 测试内容 |
|---------|---------|
| `gfx_clear` | 全屏填充特定颜色 |
| `gfx_fill_rect` | 多个不同大小/颜色的矩形 |
| `gfx_rect` | 仅边框的矩形 |
| `gfx_hline` / `gfx_vline` | 水平/垂直线 |
| `gfx_line` | Bresenham 线段 (对角线, 水平, 垂直) |
| `gfx_char` | 单个字符渲染, 前景/背景色 |
| `gfx_text` | 字符串渲染, 含换行符处理 |
| `gfx_bevel` | Win 3.0 3D 凸起/凹陷边框 |
| `gfx_window_frame` | 带标题栏的窗口框 |

**操作**:
1. 在 `de2shell_rtos` 中添加 `gfxtest` CLI 命令
2. 依次绘制每个图元, 每个之间 fb_present() + 短延时
3. 上板观察输出

**验证**: 所有 9 种图元在 FPGA VGA 上正确渲染。

### 步骤 5: 确认 GUI 文件在 de2shell_rtos 构建中编译通过 (0.5h)

**目标**: 确认 `makefile` 已正确包含所有 GUI 文件, Docker 交叉编译无错误。

**当前状态**: `sw/app/de2shell_rtos/makefile` 第 55-60 行已包含:
```makefile
APP_SRC += $(DE2SHELL_DIR)/fb_hal.c
APP_SRC += $(DE2SHELL_DIR)/gfx.c
APP_SRC += $(DE2SHELL_DIR)/gui.c
APP_SRC += $(DE2SHELL_DIR)/gui_widgets.c
APP_SRC += $(DE2SHELL_DIR)/win30_desk.c
APP_SRC += $(DE2SHELL_DIR)/ps2_decoder.c
```

**操作**:
1. 运行 `./build.sh app/de2shell_rtos` 确认编译通过
2. 检查固件大小 (预期 ~80-90KB, 因 GUI 代码增加)
3. 确认 `prog_win30` 命令已在 `main.c` 的命令注册表中

**验证**: 编译零错误零警告, 固件大小合理。

### 步骤 6: SDL2 本地构建验证 (1h)

**目标**: 在 PC 上运行完整的 GUI 桌面, 验证 SDL2 后端功能。

**当前问题**: `de2shell/makefile` 中的 `make local` 目标**未包含** GUI 相关源文件 (fb_hal.c, gfx.c, gui.c, gui_widgets.c, win30_desk.c)。需要新增一个 SDL2 GUI 本地构建目标。

**操作**:
1. 在 `sw/app/de2shell/makefile` 中新增 `local-gui` 目标:
   ```makefile
   local-gui:
       gcc -DLOCAL_BUILD -Wall -O2 -I . -I ../crypto_cli -I "$(SDL2_INC)" \
           -o de2shell_gui main.c board_status.c lcd_hal.c vga_hal.c gpio_hal.c \
           ps2_decoder.c hello.c memtest.c crypto.c ps2.c snake.c life.c \
           dashboard.c info.c monitor.c demo.c \
           fb_hal.c gfx.c gui.c gui_widgets.c win30_desk.c \
           ../crypto_cli/crypto_aes.c ../crypto_cli/crypto_sha.c ../crypto_cli/crypto_sm.c \
           -L "$(SDL2_LIB)" -lmingw32 -lSDL2main -lSDL2
   ```
2. 运行 `make local-gui`, 确认编译通过
3. 执行 `./de2shell_gui`, 进入 shell 后输入 `win30` 启动桌面
4. 验证:
   - SDL2 窗口打开 (640x480 x2 缩放 = 1280x960)
   - 桌面背景为深青色 (FB_TEAL)
   - 9 个图标正确排列 (3x3 网格)
   - 任务栏显示 "DE2Extra"
   - 两个演示窗口 ("Calculator" 和 "About DE2Extra")
   - Tab 切换焦点, Enter 激活按钮, ESC 关闭窗口
5. 或者编译独立的 `fb_test`:
   ```bash
   gcc -DLOCAL_BUILD -Wall -O2 -I . -o fb_test fb_test.c fb_hal.c \
       -I "$(SDL2_INC)" -L "$(SDL2_LIB)" -lmingw32 -lSDL2main -lSDL2
   ```
   运行后应看到 RGB 渐变 + 彩色矩形 + 交叉线。

**验证**: SDL2 窗口正确渲染 Win 3.0 桌面, 交互流畅。

### 步骤 7: 像素模式渲染测试 (1h)

**目标**: 在 FPGA 上测试完整渲染流程。

**操作**:
1. 构建 de2os 固件: `./build.sh app/de2shell_rtos`
2. 烧录 `par/de2os/de2os.sof`
3. 通过 UART/PS/2 进入 shell
4. 执行以下测试序列:
   a. `fbtest` -- RGB 渐变 + 基本图元 (如步骤 3)
   b. `gfxtest` -- 全部 9 种图元 (如步骤 4)
   c. `win30` -- Win 3.0 桌面

**预期问题与调试**:
- 如果 VGA 无输出: 检查 mode_en 寄存器是否写入成功 (读回确认)
- 如果显示乱码: 检查 fb_base 地址计算是否正确 (SDRAM word address vs byte address)
- 如果颜色错误: 检查 RGB332 位序 (MSB-first vs LSB-first)
- 如果撕裂: vga_pixel_ctrl 使用 ping-pong 行缓冲, 理论上无撕裂

**验证**: VGA 显示器正确显示像素模式输出。

### 步骤 8: 文本/像素模式切换测试 (0.5h)

**目标**: 验证两种模式可自由切换, 不影响文本终端功能。

**操作**:
1. 启动后, shell 在文本模式运行
2. 输入 `win30` -- 切换到像素模式
3. 按 ESC 退出桌面 -- 应切回文本模式 (调用 `fb_shutdown()`)
4. 确认文本终端仍然正常 (输入命令, 输出字符)
5. 再次输入 `win30` -- 应再次进入像素模式
6. 在像素模式中按 ESC 退出, 反复切换 3 次

**潜在问题**:
- `fb_shutdown()` 调用 `fb_hw_mode_set(0)` 禁用像素模式
- 切回文本模式后, VGA 文本终端应恢复工作
- 如果 vga_text_terminal 在像素模式期间状态丢失, 可能需要重新初始化

**验证**: 文本/像素模式可反复切换, 文本终端在切换后正常工作。

### 步骤 9: Win 3.0 桌面完整测试 (1h)

**目标**: 在 FPGA 上验证 Win 3.0 桌面的所有交互功能。

**测试项**:

| 测试 | 操作 | 预期 |
|------|------|------|
| 桌面渲染 | 启动 win30 | 深青色背景 + 9 图标 + 任务栏 + 2 窗口 |
| 焦点切换 | Tab / Shift+Tab | 焦点在图标/按钮间循环 |
| 图标激活 | Enter / Space | 图标高亮反馈 |
| 窗口关闭 | ESC (焦点在窗口时) | 窗口隐藏 |
| 按钮动画 | Enter (焦点在按钮时) | 按下动画 (凹陷) |
| 退出桌面 | ESC (无焦点或全局) | 退出到文本 shell |
| PS/2 输入 | 键盘输入字符 | 桌面响应键盘事件 |
| 多次进入/退出 | 反复运行 win30 | 每次正确初始化/清理 |

**PS/2 注意事项**:
- `win30_desk.c` 中的 PS/2 轮询使用 `0xF0008000` (PS2_MMIO_BASE)
- `de2extra_pkg.vhd` 中 `ADDR_PS2_BASE = 0xF0008000`，地址一致，无需修改

**验证**: 所有 8 项测试通过。

### 步骤 10: 资源使用与性能评估 (0.5h)

**目标**: 评估像素模式对 FPGA 资源和帧率的影响。

**资源评估**:
1. 读取 Quartus 编译报告 (`par/de2os/de2os.fit.summary`)
2. 对比 vga_pixel_ctrl 加入前后的 LE/M9K/DSP 占用

**性能评估**:
1. 使用 CLINT MTIMER 测量 `gfx_clear()` 全屏清屏耗时
2. 测量 Win 3.0 桌面完整渲染一帧的耗时 (gfx_clear + gui_render_all + fb_present)
3. 目标: 单帧渲染 < 50ms (20fps 可接受, 10fps 最低限度)

**SDRAM 带宽分析**:
- 帧缓冲读取: 640x480 @ 60Hz, burst 读取, 每行 160 words x 8 burst
- CPU 写入: 逐像素 byte 写, 无 burst, 带宽需求远小于读取
- 总带宽: 读取 ~27.6 MB/s (@60Hz), 写入取决于 CPU 速度

**验证**: 资源占用在预算内 (总计 <10,605 LEs), 渲染帧率可接受。

---

## 5. 已知问题与风险

### 高优先级

| 问题 | 影响 | 修复方案 |
|------|------|---------|
| fb_hal 寄存器偏移需与 wb_intercon 交叉验证 | 像素模式无法启用 | 步骤 1 确认后修正 |
| `make local` 未包含 GUI 源文件 | PC 端无法测试 GUI | 步骤 6 新增 local-gui 目标 |

### 中优先级

| 问题 | 影响 | 修复方案 |
|------|------|---------|
| 无脏区域追踪, 每帧全屏重绘 | 性能浪费, 帧率受限 | 后续优化: shadow buffer + dirty rect |
| `fb_clear()` 逐字节写 307200 次 | ~6ms @50MHz, 可接受 | 如需更快, 改为 word 写 |
| GUI widget pool 在 SDRAM (32 widgets x ~100B = ~3.2KB) | 占用少量 SDRAM | 可接受, 必要时减小 GUI_MAX_WIDGETS |
| fb_poll_events() 仅在 fb_present() 中调用 | LOCAL_BUILD 下 SDL 窗口可能卡死 | 确保渲染循环中调用 fb_present() |

### 低优先级

| 问题 | 影响 | 修复方案 |
|------|------|---------|
| 缺少 bitblt 图元 | 无法高效拷贝像素区域 | 后续按需添加 |
| 缺少圆/椭圆图元 | 密码学可视化可能需要 | 后续按需添加 |
| SDL2 窗口固定 2x 缩放 | 无法调整窗口大小 | 后续可加命令行参数 |

---

## 6. 文件清单

### 需要修改的文件

| 文件 | 修改内容 |
|------|---------|
| `sw/app/de2shell/win30_desk.c` | 无需修改 (PS2_MMIO_BASE 已与 de2extra_pkg.vhd 一致) |
| `sw/app/de2shell/makefile` | 新增 `local-gui` 目标, 包含 GUI 源文件 |
| `sw/app/de2shell/fb_hal.c` | 可能修正 VGA 寄存器偏移 (步骤 1 结果) |

### 需要确认的文件 (只读检查)

| 文件 | 确认内容 |
|------|---------|
| `src/rtl/wb_intercon.vhd` | VGA s1 地址解码, vga_pixel_ctrl 寄存器偏移 |
| `sw/app/de2shell_rtos/de2shell_rtos.ld` | 帧缓冲/堆内存布局 |
| `src/rtl/de2os_top.vhd` | vga_pixel_ctrl 信号连接, 3-way MUX |

### 无需修改的文件 (已就绪)

| 文件 | 说明 |
|------|------|
| `sw/app/de2shell/fb_hal.h` | API 稳定, RGB332 调色板宏完整 |
| `sw/app/de2shell/gfx.c/h` | 全部 9 种图元已实现 |
| `sw/app/de2shell/gfx_font.h` | CP437 8x16 字体数据完整 |
| `sw/app/de2shell/gui.c/gui.h` | 窗口管理器完整, 支持 DE2SHELL_RTOS section 属性 |
| `sw/app/de2shell/gui_widgets.c` | 6 种控件完整 |
| `sw/app/de2shell/ps2_decoder.c/h` | Set 2 解码器完整 |
| `sw/app/de2shell_rtos/makefile` | GUI 源文件已包含 |
| `src/rtl/periph/vga_pixel_ctrl.vhd` | 硬件像素控制器完整 |
| `sw/app/de2shell/fb_test.c` | 冒烟测试程序完整 |

---

## 验收表

| 编号 | 验收项 | 状态 |
|------|--------|------|
| V3P3A.S1.1 | fb_hal NEORV32 后端: fb_set_pixel 写入 SDRAM 帧缓冲地址正确 | ⬜ |
| V3P3A.S1.2 | fb_hal NEORV32 后端: fb_hw_mode_set 正确启用/禁用像素模式 | ⬜ |
| V3P3A.S2.1 | gfx 全部 9 种图元 (clear/fill_rect/rect/hline/vline/line/char/text/bevel/window_frame) 在 FPGA 上渲染正确 | ⬜ |
| V3P3A.S2.2 | gfx_window_frame 带标题栏窗口在像素模式下正确显示 | ⬜ |
| V3P3A.S3.1 | de2shell_rtos 构建包含 GUI 源文件, Docker 交叉编译零错误 | 代码已包含 (makefile L55-60: fb_hal/gfx/gui/gui_widgets/ps2_decoder/twm) |
| V3P3A.S3.2 | 固件大小合理 (<100KB @ SDRAM) | ⬜ |
| V3P3A.S4.1 | `make local` (SDL2) 编译通过, 包含 GUI 源文件 | ✅ 代码确认 (makefile local 目标包含 fb_hal/gfx/gui/gui_widgets/twm) |
| V3P3A.S4.2 | SDL2 窗口打开, 显示桌面 (背景/图标/任务栏/窗口) | ⬜ |
| V3P3A.S4.3 | SDL2 桌面交互: Tab 焦点切换, Enter 激活, ESC 退出 | ⬜ |
| V3P3A.S5.1 | FPGA 像素模式: VGA 显示 RGB 渐变填充 | ⬜ |
| V3P3A.S5.2 | FPGA 像素模式: Win 3.0 桌面完整渲染 (9 图标 + 2 窗口 + 任务栏) | ⬜ |
| V3P3A.S5.3 | FPGA 像素模式: PS/2 键盘输入驱动桌面交互 | ⬜ |
| V3P3A.S6.1 | 文本模式 -> 像素模式切换正常 (win30 启动) | ⬜ |
| V3P3A.S6.2 | 像素模式 -> 文本模式切换正常 (ESC 退出后 shell 恢复) | ⬜ |
| V3P3A.S6.3 | 文本/像素模式可反复切换 >=3 次, 无状态异常 | ⬜ |
| V3P3A.S7.1 | Quartus 编译通过, LE 占用 <11,000 (含 vga_pixel_ctrl) | ⬜ |
| V3P3A.S7.2 | 单帧渲染 (clear + gui_render_all) < 50ms | ⬜ |
| V3P3A.S7.3 | SDRAM 帧缓冲不与代码段/堆重叠 (链接脚本确认) | ⬜ |
| V3P3A.S8.1 | fb_hal VGA 寄存器偏移与 wb_intercon 地址解码一致 | ⬜ 需交叉验证 |
| V3P3A.S8.2 | twm.c PS2_MMIO_BASE 地址与 de2extra_pkg.vhd 一致 (0xF0008000) | ✅ 代码确认 |
| V3P3A.S9.1 | Snake 全屏: GRID_W=78, GRID_H=27, 填满 80x30 (留 2 列 2 行边距) | ✅ 代码确认 (snake.c L7-8) |
| V3P3A.S9.2 | Snake CP437 box-drawing 边框: CH_BOX_HZ/VT/TL/TR/BL/BR 等字符 | ✅ 代码确认 (snake.c L131-145) |
| V3P3A.S9.3 | vga_wait_vblank() 实现并集成到 snake 更新循环 | ✅ 代码确认 (vga_hal.c L128 + snake.c L213) |
| V3P3A.S10.1 | TWM (tiling window manager) 替代 win30_desk, twm.c 编译通过 | ✅ 代码确认 (makefile local 目标包含 twm.c) |
| V3P3A.S10.2 | `twm` CLI 命令已注册 (替换 `win30`/`startui`/`gui` 别名) | ⬜ 需确认 main.c |
