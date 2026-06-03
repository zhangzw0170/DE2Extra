# V3P8: TWM 像素模式刷新性能优化

> 状态: **规划中**
> 依赖: V3P7 (synth 音频验收)
> 目标: TWM 交互操作达到 15-30 FPS

## 问题分析

当前 TWM 刷新瓶颈：

- `gfx_fill_rect()` 逐像素写 SDRAM，每次 CPU 写 = Wishbone 总线事务 (~3-5 cycle)
- `tile_render_all()` 每次布局变化重绘**全屏** 640×480 = 300K 像素
- 文字渲染：每个 8×16 字符 = 128 次像素写，一行标题 ~500 次
- 实测：全屏刷新需数秒，交互不可用

系统已有但未充分利用的资源：

- **GPU 2D 加速器** (`gpu_2d.vhd`, 0xF0015000): FILL rect via SDRAM burst-write, 对齐约束: x 偶数, w 偶数, w%16==0, w>=16
- **VGA text terminal** (0xF0000000): 已有硬件字符渲染 (80×30, 字符单元模式)
- **SDRAM**: 128MB, 双端口 (CPU + VGA controller 各自独立端口)

## 调研参考

| 系统 | 技术 | 借鉴点 |
|------|------|--------|
| Amiga Blitter | DMA 驱动矩形填充/复制 | GPU burst-fill 已实现此模式 |
| LVGL | 脏矩形追踪 (`lv_inv_area`) | 只重绘变化区域 |
| TouchGFX | Partial framebuffer | 渲染到小缓冲区再写入 |
| ScummVM | Dirty rectangle system | 实用的脏矩形合并算法 |
| tangyRiscVSOC | RISC-V + 2D blitter (FPGA) | 开源参考实现 |
| Atari ANTIC | Display list (DMA 命令队列) | GPU 命令 FIFO 的原型 |
| Arm Mobile GPU | Tile-based rendering | 分块渲染减少带宽 |

## 实施阶段

### P0: GPU 加速所有矩形填充 (预期: 0.5→5-10 FPS)

**工作量**: 1-2h | **改动**: 纯软件

修改 `gfx_fill_rect()` 在满足 GPU 对齐约束时走 `gpu_fill_rect()`:

```
约束: w>=16, h>=1, x 偶数, w 偶数, w%16==0
```

已有代码在 `gfx.c:28-41` 尝试走 GPU，但条件可能过严。需检查：
- TWM 窗口尺寸是否满足对齐 (通常 w>=60, 通常是偶数)
- 不满足时回退到 CPU 逐像素写 (可接受，小矩形影响不大)
- `gpu_wait()` 是否可延迟到批量操作结束

**涉及文件**: `sw/lib/gfx.c`, `sw/lib/gpu.c`

### P1: 消除全屏 clear + 瓦片级脏矩形 (预期: 焦点切换 10x)

**工作量**: 3-4h | **改动**: 纯软件

1. **去掉全屏 clear**: `tile_render_all()` 目前先 `gfx_fill_rect(全屏, BLACK)`，改为只填充变化的瓦片
2. **脏矩形追踪**: TWM 已有 `redraw_pending` 标志，扩展为脏矩形列表

```
脏矩形来源:
- tile_split(): 新兄弟 + 父分割线区域
- tile_close(): 兄弟扩展后的新区域
- tile_focus_dir()/tile_focus_cycle(): 仅新旧焦点瓦片的标题栏
- tile_resize(): 受影响瓦片区域
- tile_toggle_fullscreen(): 全屏切换的瓦片
```

3. **渲染时裁剪**: 只重绘与脏矩形相交的瓦片区域

**涉及文件**: `sw/lib/gui.c`, `sw/lib/twm.c`

### P2: 文本渲染加速 (预期: 文字操作 20x)

**工作量**: 2-3h | **改动**: 软件 + 少量 RTL

**方案 A (推荐): 复用已有 VGA text terminal**

TWM 状态栏和标题栏使用现有 text terminal (80×30 字符单元模式)，
像素模式仅用于瓦片内容区域。VGA 输出 mux 优先级:
text > pixel，状态栏区域由 text terminal 渲染 (零 CPU 文字开销)。

**方案 B: BRAM 字符叠加层**

在 VGA pixel pipeline 中添加一个小型 BRAM 字符网格 (80×30 = 9.6KB M9K)，
scanout 时硬件合成字符。CPU 每字符写 1 个 32-bit word 替代 ~80 个 16-bit 像素写。

**涉及文件**: `sw/lib/gui.c`, `src/rtl/periph/vga_pixel_ctrl.vhd` (方案 B)

### P3: GPU 命令 FIFO (预期: 多矩形批量 3-5x)

**工作量**: 4-8h | **改动**: RTL + 软件

为 `gpu_2d.vhd` 添加 8-16 深度的命令 FIFO (BRAM):
- CPU 连续写入多条 FILL 命令 (6 words/条)，无需等待
- GPU 自动从 FIFO 取命令执行
- 新增 "FIFO empty" 状态位，CPU 仅最后一次 poll

**参考**: Atari ANTIC display list, NXP i.MX31 2D GPU

**涉及文件**: `src/rtl/periph/gpu_2d.vhd`, `sw/lib/gpu.c`

### P4: GPU Blit/Copy 操作 (预期: 窗口移动 10x)

**工作量**: 4-8h | **改动**: RTL + 软件

为 GPU 添加 COPY 操作码:
- 新增 `GPU_REG_SRC_ADDR` 寄存器
- GPU 从 src SDRAM 读 → dst SDRAM 写 (矩形复制)
- 用于瓦片比例调整时移动未变化的窗口内容

**参考**: Amiga Blitter BitBLT, netbust3r/2D-Graphics-Accelerator-FPGA

**涉及文件**: `src/rtl/periph/gpu_2d.vhd`, `sw/lib/gpu.c`, `sw/lib/gfx.c`

## 性能预估

| 操作 | 当前 | P0+P1 后 | P0-P4 后 |
|------|------|----------|----------|
| 焦点切换 (标题栏) | ~3s | ~50ms (20 FPS) | ~5ms (200 FPS) |
| 水平分割 | ~5s | ~100ms (10 FPS) | ~20ms (50 FPS) |
| 关闭窗口 | ~5s | ~100ms (10 FPS) | ~15ms (66 FPS) |
| 调整比例 | ~5s | ~80ms (12 FPS) | ~10ms (100 FPS) |

## 开源参考

- [tangyRiscVSOC](https://github.com/qubeck78/tangyRiscVSOC) — RISC-V SoC + 2D blitter + VGA text+gfx
- [netbust3r/2D-Graphics-Accelerator-FPGA](https://github.com/netbust3r/2D-Graphics-Accelerator-FPGA) — VHDL 2D 加速器
- [dirtyrects](https://github.com/rettetdemdativ/dirtyrects) — C 脏矩形库
- [LVGL](https://github.com/lvgl/lvgl) — 嵌入式 GUI 框架，脏矩形追踪参考
- [GPLGPU](https://jbush001.github.io/2016/07/24/gplgpu-walkthrough.html) — GPU display list 架构
- [MDPI: 2D Graphics Accelerator for Embedded Systems](https://www.mdpi.com/2079-9292/10/4/469) — 学术论文

## 历史记录

- **2026-06-03**: 规划文档创建，调研完成
