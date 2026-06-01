# Phase 6: GPU 2D 硬件加速器 + VGA PLL 时钟修复

> 日期: 2026-06-01 | 状态: **RTL+C 完成，Quartus 编译中**
> 优先级: P0 (VGA 像素模式是后续所有 GUI 工作的前置依赖)

---

## 1. GPU 2D 加速器

### 1.1 动机

TWM 像素模式每帧刷新耗时 ~2 秒。逐层瓶颈分析：

1. **CPU 写 framebuffer**: fb_set_pixel 每次写 2 字节到 SDRAM，640×480 = 307,200 次写
2. **CPU 指令获取**: ICACHE 关闭，每条指令从 SDRAM 取（~300ns），每像素 ~31 次 SDRAM 访问
3. **排除的替代方案**: ICACHE burst 与 sdram_ctrl toggle handshake 冲突（已尝试，不可行）；SDRAM open-page 优化治标不治本

GPU 方案加速比：**~400x**（CPU 逐像素 ~1.2s → GPU burst ~3ms 全屏填充）

### 1.2 架构

```
CPU (50MHz) ──→ wb_intercon (s12) ──→ gpu_2d (寄存器配置)
                                       │
                                       └─ FSM (100MHz) ──→ sdram_ctrl (burst-write 端口)
                                                              │
                                                              └─ 8 words/burst = 16 pixels/burst
```

### 1.3 寄存器映射

| 偏移 | 名称 | R/W | 说明 |
|------|------|-----|------|
| 0x00 | CONTROL | W | [1:0] opcode: 0=nop, 1=FILL (写触发) |
| 0x04 | STATUS | R | [0] busy |
| 0x08 | DST_ADDR | R/W | [31:0] 目标字节地址 |
| 0x0C | WIDTH | R/W | [15:0] 每行像素数 |
| 0x10 | HEIGHT | R/W | [15:0] 行数 |
| 0x14 | DST_STRIDE | R/W | [15:0] 行步长 (bytes) |
| 0x18 | COLOR | R/W | [15:0] RGB565 填充色 |

### 1.4 FSM (100MHz 域)

```
G_IDLE ──(start_fire)──→ G_ROW_SETUP
  ↑                         │
  │                    ┌────┴─────┐
  │                    │ row=0?   │
  │                    │ Y: IDLE  │ N: col=width
  │                    └────┬─────┘
  │                         ↓
  │                    G_BURST_REQ ──(req)──→ G_BURST_WAIT
  ↑                         ↑                    │
  │                         │          (gpu_wr_done)
  │                    ┌────┴────┐         addr += 8
  │                    │col>16?  │              │
  │                    │Y: again │ N: G_ROW_NEXT│
  │                    └─────────┘              │
  │                                   row--, addr += stride-width
  └─────────────────────────────────────────────┘
```

### 1.5 SDRAM 集成

sdram_ctrl 新增第 4 条路径: GPU burst-write。
仲裁优先级: CPU burst > VGA burst-read > **GPU burst-write** > CPU single-word。

### 1.6 CDC

- start 信号: 50MHz → 100MHz，2-FF 同步 + toggle 边沿检测
- busy 信号: 100MHz → 50MHz，2-FF 同步

### 1.7 文件清单

| 文件 | 说明 |
|------|------|
| `src/rtl/periph/gpu_2d.vhd` | GPU RTL (262 行) |
| `sw/lib/gpu.h` | 寄存器定义 + API |
| `sw/lib/gpu.c` | 驱动实现 (LOCAL_BUILD stub + NEORV32 MMIO) |
| `src/rtl/periph/sdram_ctrl.vhd` | 新增 gpu_wr_* 端口 |
| `src/rtl/bus/wb_intercon.vhd` | s12 slave @ 0xF0015000 |
| `src/rtl/lib/de2extra_pkg.vhd` | ADDR_GPU_BASE |
| `src/rtl/de2os_top.vhd` | 实例化 + 连线 |

### 1.8 软件集成

- `fb_clear()` 已改用 `gpu_fill_rect()` + `gpu_wait()`
- `gfx_fill_rect()` 对大矩形用 GPU 加速，小矩形 CPU fallback
- LOCAL_BUILD 下 GPU 函数为空 stub (SDL2 路径不受影响)

---

## 2. VGA PLL 时钟修复 (2026-06-01)

### 2.1 问题

VGA 文本模式出现"斜线"重影，**每次 UART TX 闪烁就出现一次**。
原因: toggle flip-flop 生成的 25MHz 时钟经过普通逻辑资源路由，受 UART TX 开关噪声干扰导致时序抖动。

### 2.2 修复

将 VGA 25MHz 时钟从 toggle flip-flop 改为 **PLL c3 输出** (专用全局时钟网络，完全隔离逻辑噪声)。

同时改进输出寄存器:
- **之前**: 在 50MHz 上升沿检测 `clk_25m='1'`（间接检测下降沿）
- **现在**: 直接在 `falling_edge(clk_25m_i)` 锁存所有 VGA 信号（数据在 DAC 采样前稳定 20ns）

### 2.3 改动文件

| 文件 | 改动 |
|------|------|
| `src/ip/altpll_50_100.vhd` | 新增 c3=25MHz 输出 |
| `src/rtl/glue/clk_rst_gen.vhd` | 新增 clk_25m_o，路由 PLL c3 |
| `src/rtl/periph/vga_text_terminal.vhd` | 删除内部 toggle，新增 clk_25m_i 端口，输出寄存器改 falling_edge |
| `src/rtl/periph/vga_pixel_ctrl.vhd` | 同上 |
| `src/rtl/de2os_top.vhd` | 新增 clk_25m 信号，连接 PLL → VGA 模块 |

### 2.4 PLL 配置

| 输出 | 频率 | 相位 | 用途 |
|------|------|------|------|
| c0 | 50MHz | 0° | CPU + Wishbone |
| c1 | 100MHz | 0° | SDRAM 控制器内部 |
| c2 | 100MHz | +1.56ns | DRAM_CLK 引脚 |
| **c3** | **25MHz** | **0°** | **VGA pixel clock** |

---

## 3. 验证 (2026-06-01)

- [x] Quartus 编译通过，0 error，timing met
- [x] pxtest SDRAM 回读 0/2560 错误
- [x] VGA burst read valid/req ≈ 8 (数据通路正确)
- [x] TWM 30 秒稳定运行
- [x] pxtest 显示器可见棋盘格+渐变色 (数据通路完整)
- [ ] ~~UART TX 期间 VGA 文本无斜线重影~~ — **BUG: PLL c3 单路未解决，需双 PLL 输出**
- [ ] TWM 像素模式画面质量 — **BUG: 与修复前相同，待进一步排查**
- [ ] GPU fill 性能测试 (全屏填充 < 10ms)

### 已确认的 Bug (2026-06-01)

**BUG-1: VGA 文本模式斜线重影**
- 现象: UART TX 输出时 VGA 文本出现斜线重影
- PLL c3 25MHz 单路修复未解决
- 下一步: 双 PLL 输出 (c3=25MHz 0° + c4=25MHz -90°)，参考 Terasic 例程

**BUG-2: TWM 像素模式显示异常**
- 现象: TWM 画面与 PLL 修复前相同
- 数据通路已验证正确 (SDRAM 回读 0 错误, burst read 正常, framebuffer 内容正确)
- pxtest 基本图案 (棋盘格+渐变) 可见
- 可能与 BUG-1 同根因 (时钟耦合/DAC 时序)
