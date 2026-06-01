# de2os FreeRTOS 集成状态

> 日期: 2026-06-01
> 状态: **VGA PLL 修复已部署，像素模式数据通路验证通过**
> 更新: 2026-06-01 — PLL c3 25MHz + falling_edge 输出寄存器已部署；SDRAM 回读 0/2560 错误；VGA burst read valid/req≈8；TWM 30s 稳定运行；待用户肉眼验证显示器画面质量
> 硬件工程: `par/de2os/` (top entity: `de2os_top`)
> 目标固件: `sw/app/de2shell_rtos/`

## 当前结论

VGA PLL 修复已部署：toggle flip-flop → PLL c3 25MHz (专用全局时钟网络)，输出寄存器改用 falling_edge。SDRAM 回读测试 0/2560 错误，VGA burst 读 valid/req≈8（每次 burst 返回 8 words 正确），TWM 运行 30 秒无崩溃。数据通路完整验证通过。待用户肉眼确认显示器画面质量。

当前构建：
- 固件: ~150KB (GPU + 改进 pxtest)
- RTL: `par/de2os/de2os.sof` (已烧录)
- PLL: c0=50MHz, c1=100MHz, c2=100MHz(+1.56ns), c3=25MHz(VGA)

## 已完成

### 0. GPU 2D 加速器 + VGA PLL 修复 (2026-06-01)

详见 `doc/phases/phase6-gpu-2d.md`。

- **GPU 2D**: RTL (gpu_2d.vhd) + C 驱动 (gpu.h/gpu.c) + SDRAM burst-write 端口 + 总线集成 (s12 @ 0xF0015000)
- **VGA PLL**: 25MHz 时钟从 toggle flip-flop 改为 PLL c3 输出，输出寄存器改用 falling_edge
- fb_clear() 已使用 GPU 加速，gfx_fill_rect() 大矩形走 GPU
- **上板验证**: Quartus 编译通过 (0 error)，烧录成功
- **pxtest 诊断改进**: 修正 16-bit packed counter 解读；新增 SDRAM 回读验证 (0/2560 错误)；新增 framebuffer 采样 + live display 快照
- **数据通路验证**:
  - SDRAM 回读: 0/2560 mismatches (CPU 32-bit write/read 完美)
  - Framebuffer 采样: line 100 前 16 像素值与预期 gradient 匹配
  - VGA burst read: valid_word/burst_req ≈ 8 (每次 burst 正确返回 8 words)
  - Live display: disp_word_q 包含有效 RGB565 gradient 数据
- **TWM 稳定性**: 30 秒运行无崩溃，ESC 干净退出

### 1. SDRAM 执行基线已建立

- `de2os` 使用 bootloader 上传固件到 SDRAM，再从 `0x01000000` 执行。
- 这条路线已经绕开裸机 `de2shell` 的 `IMEM 64KB` 上限。
- `sw/app/de2shell_rtos/makefile` 已将 `__neorv32_rom_size` 提到 `128M`。

### 2. FreeRTOS heap 已移出 16KB DMEM

FreeRTOS 内核通过 NEORV32 上游集成的 RISC-V port 提供（`neorv32/sw/ext/`），FreeRTOS+CLI 作为本地源文件集成在 `sw/app/de2shell_rtos/FreeRTOS_CLI.c` / `FreeRTOS_CLI.h`，不使用子模块。

当前修复：

- `configAPPLICATION_ALLOCATED_HEAP = 1`
- `configTOTAL_HEAP_SIZE = 16384`
- 新增 `sw/app/de2shell_rtos/rtos_memory.c`
- 链接脚本新增 `.freertos_heap` 段，放到 `0x01900000`

### 3. framebuffer 已与代码区分离

- framebuffer 移到 `0x01800000`
- FreeRTOS heap 放在 `0x01900000`

### 4. VGA 像素模式已接通软件控制

- `vga_text_terminal` 和 `vga_pixel_ctrl` 共享同一 VGA Wishbone 窗口
- 文本控制寄存器移到 `0x1F40..0x1F54`
- 像素控制寄存器使用 `0x1F80..`
- `fb_hal.c` 已改为启动时默认开启 test pattern (bit 1)，用于诊断 VGA 信号路径
- **2026-05-31: TWM 命令首次在物理显示器上显示像素模式内容！** 但画面花屏/刷新慢，SDRAM 帧缓冲读取可能有竞争问题。这是重要突破——信号路径已通。

### 5. PS/2 已接入 RTOS 输入队列（主输入源）

- `t_uart_input()` 同时轮询 UART + PS/2 MMIO
- 排除机制: PROG_PS2 / PROG_WIN30 / PROG_PONG_HW 的 PS/2 轮询由各自程序负责，不经过 t_uart_input

### 6. RTOS 版本的程序集已完成集成

所有程序已注册 CLI 命令，makefile 已同步：

| CLI 命令 | 程序 | 说明 |
|----------|------|------|
| hello | prog_hello | LED chaser |
| memtest | — | SDRAM diagnostic (built-in) |
| crypto | prog_crypto | AES/SHA/SM4 CLI + bench |
| ps2 (kbd) | prog_ps2 | PS/2 keyboard test |
| snake | prog_snake | Snake game (1P/2P, WASD+箭头, F10退出) |
| life (conwaylife) | prog_life | Conway software implementation |
| info | prog_info | System dashboard |
| monitor (riscvasm) | prog_monitor | Memory/register monitor |
| expdemo (demo) | prog_demo | 13 course labs (Exp1-13 全可用) |
| twm | prog_twm | Tiling window manager (像素模式 GUI) |
| conwayhw | prog_conway_hw | Conway 硬件引擎 |
| ponghw | prog_pong_hw | PONG 硬件引擎 + VGA |
| ntt | prog_ntt | NTT 加速器 CLI |
| synth | prog_synth | Audio synth (PS/2 钢琴键盘) |
| chroma | prog_chroma | ChromaShader 地形沙盒 (HW 噪声 + MMIO) |
| pxtest | — | VGA 像素模式诊断 (5-phase) |
| vgadump | — | VGA framebuffer dump |
| vgam | — | VGA mode query |
| stats | — | Task list + stack HWM |
| heapstat | — | Heap usage |
| cpustat | — | CPU usage per task |
| clear | — | Clear VGA screen |

### 7. C 驱动完成 (synth.c)

Audio synth C 驱动 (`sw/app/de2shell/synth.c`): 88 音符 tuning table, PS/2 双轨钢琴键盘映射, 3xOSC/DX7 模式切换, 预设加载, Tab/Caps/NumLock 八度切换, Q/ESC 退出静音。CLI 命令 `synth` 已注册 (第 21 个命令)。待固件重编译 + 上板验证。

### 8. RTL 外设已全部集成 (2026-05-29)

以下外设在 `de2os_top.vhd` 中已从 stub 升级为实际实例化：

| 外设 | 状态 | 说明 |
|------|------|------|
| ntt_sdf | ☑ 实例化 | Wishbone slave s4 @ 0xF000F000 |
| pong_engine | ☑ 实例化 | Wishbone slave s9 + VGA 输出信号 |
| conway_engine | ☑ 实例化 | Wishbone slave s10 |
| INTC s7 | ☑ 修复 | ack loopback (不再挂死总线) |
| synth_engine | ☑ 实例化 | Wishbone slave s11 @ 0xF0013000, AUD/I2C pins |
| Exp6/7 VGA 适配器 | ☑ 实例化 | adapt_exp6/7 + vga_test_pattern, VGA 输出 mux (exp>pong>pixel>text) |

### 9. ChromaShader RTL + 仿真完成 (2026-05-30)

RTL 噪声地形生成器 (`chroma_shader.vhd`, ~450 行) + C MMIO 驱动 (`chroma.c`) + 总线集成已完成：

| 组件 | 文件 | 状态 |
|------|------|------|
| RTL 模块 | `src/rtl/periph/chroma_shader.vhd` | ✅ vcom 0 error |
| 总线集成 | `wb_intercon.vhd` s12, `de2extra_pkg.vhd` | ✅ 基地址 0xF0014000 |
| 顶层连线 | `de2os_top.vhd` | ✅ WB + VGA 侧 |
| VGA 终端覆盖 | `vga_text_terminal.vhd` | ✅ 6 新增端口 |
| C 驱动 | `sw/app/de2shell_rtos/chroma.c` | ✅ MMIO + LOCAL_BUILD |
| RTOS 注册 | `main.c`, `makefile` | ✅ CLI 命令 `chroma` |
| QuestaSim 仿真 | `sim/chroma_shader_tb.vhd` | ✅ 10/10 通过 (19 checks) |

修复的关键 Bug: meta_ram 多驱动冲突 (两个进程写同一信号 → metavalue), rgb332_to_565 位宽错误。

待: Quartus 编译 + 固件编译 + 上板验证。详见 `doc/phases/v3p5.md`。

### 10. Bug 修复 (2026-05-29/30)

| 问题 | 修复 | 文件 |
|------|------|------|
| crypto bench 卡死 | `trng_bytes()` 无 `trng_available()` 检查 → 无限 busy-loop | `crypto.c` |
| twm 卡死 | PS/2 竞争: t_uart_input 和 tiling_update 同时轮询 PS/2 MMIO | `main.c` 排除列表 |
| ntt.c NEORV32 编译失败 | `ntt_a[]` 仅在 LOCAL_BUILD 下声明，NEORV32 路径改用直接 MMIO | `ntt.c` |
| INTC 0xF000A000 访问挂死 | s7_ack_i = '0' → 总线无响应；改为 ack loopback | `de2os_top.vhd` |
| I2C SDA 总线竞争 | I2C_SDAT 从 out 改为 inout 三态缓冲，防止 FPGA 拉高与 slave ACK 冲突 | `wm8731_ctrl.vhd`, `synth_engine.vhd`, `de2os_top.vhd`, `de2os_imem_top.vhd` |

### 11. PS/2 TUI 增强 + Snake 2P + 全局 Fn 键 (2026-05-30)

PS/2 虚拟键码系统：22 个 VK 常量 (F1-F12, 方向键, 导航键)，门控条件修改使非 ASCII 键到达程序。全局 Fn 键绑定：F1=帮助、F10=退出。所有程序 Q 键退出已移除。Snake 支持双人模式 (WASD + 方向键)。详见 `doc/phases/v3p6.md`。

| 组件 | 状态 |
|------|------|
| PS/2 VK 常量 + F1-F12 解码 | ✅ ps2_decoder.h/c |
| 输入门控修改 | ✅ main.c |
| 全局 F1 帮助 + F10 退出 | ✅ main.c t_active_prog |
| Snake 2P 模式 | ✅ snake.c 完全重写 |
| Chroma 方向键 + F10 | ✅ chroma.c |
| Q 退出全面移除 | ✅ 13 个程序 |
| 编译 | ✅ bin |
| 上板验证 | ⏳ 待验证 |

## 当前剩余问题

### P0. VGA 像素模式 (2026-06-01 更新 — 数据通路已验证，显示质量 Bug 待修)

**2026-06-01 (PLL 修复)**: 根因确认 — UART TX 噪声通过逻辑资源耦合到 toggle flip-flop 生成的 25MHz 时钟。修复: PLL c3 输出 25MHz (专用时钟网络) + falling_edge 输出寄存器。**但文本模式斜线重影未消除。**
**2026-06-01 (pxtest 诊断)**: SDRAM 回读 0/2560 错误，VGA burst read valid/req≈8，framebuffer 采样与预期匹配，live display 快照包含有效 RGB565 数据。**pxtest 显示器可见棋盘格+渐变色。**
**2026-06-01 (TWM 测试)**: 30 秒稳定运行，无崩溃，ESC 干净退出。**但显示器画面与修复前相同，仍有问题。**
**2026-06-01 (用户确认 Bug)**:
- BUG-1: 文本模式 UART TX 期间仍有斜线重影 (PLL c3 单路未解决)
- BUG-2: TWM 像素模式显示与修复前相同 (数据通路正确但显示质量差)
- 下一步: 双 PLL 输出 (c3=25MHz 0° + c4=25MHz -90°) 或调查 DAC 输出路由/去耦

### P1. 上板验证 (2026-06-01 更新)

- [x] bootloader 上传 + SDRAM 执行 — ✅ 150KB 固件上传成功
- [x] FreeRTOS 4 任务调度正常 — ✅ stats 显示 4 任务 + 栈 HWM 正常
- [x] shell UART 输入 — ✅ UART 输入到达 shell，命令解析正常
- [x] VGA 文本终端 80×30 显示 — ✅ vgadump 快照正常
- [x] help/stats/heapstat/cpustat/clear — ✅ UART+vgadump 验证通过
- [x] hello/info/life 交互式程序 — ✅ ESC 退出正常
- [x] twm 进入/像素模式显示 — ✅ 30 秒稳定运行
- [x] pxtest 诊断 VGA 像素模式 — ✅ SDRAM 回读 0 错误，burst read 正常
- [ ] twm 画面质量 — 🟡 待用户肉眼验证
- [ ] VGA 文本模式重影 — 🟡 待用户肉眼确认 PLL 修复效果
- [ ] crypto bench (TRNG 修复后不再卡死) — 待测试
- [ ] conwayhw / ponghw / ntt 基本功能 — 待测试
- [ ] ExpDemo 13 个实验 (含 Exp6/7 VGA 测试图案) — 待测试
- [ ] I2C SDA 三态修复后 audio synth 初始化 — 待测试

### P2. PS/2 VK 已基本覆盖，组合键待完善

V3P6 已添加 22 个 VK 常量 (F1-F12, 方向键, 导航键)，程序可通过 `(uint8_t)c == PS2_VK_xxx` 接收。但 Ctrl+字母、Alt+字母等组合键尚未映射。如果后续 GUI 需要更丰富的键盘事件，可扩展 VK 范围或改用 event 结构体。

### P3. 无双缓冲

像素模式仍是单 framebuffer。理论上会有撕裂风险，但这不是当前启动阻塞项。

### P4. Audio synth RTL+C 均已完成，待上板验证

RTL + C 驱动均已完成 (synth_engine @ s11, synth.c CLI)。待固件重编译 + 上板验证:
1. I2C 配置 WM8731 → I2S 输出 → 耳机可听
2. PS/2 键盘弹奏测试

## 下一步

1. **用户验证 VGA 画面质量**: 检查文本模式重影是否消除、像素模式画面是否正确
2. 如像素模式仍有问题: 实现像素采样回传 (串口 → 上位机分析) 或考虑 Terasic 双 PLL 输出方案 (c3=25MHz 0° + c4=25MHz -90°)
3. 验证 crypto/twm/conwayhw/ponghw/ntt/synth 基本功能
4. ChromaShader: Quartus 编译 + 上板验证
5. GPU 性能测试: 全屏填充时间测量
3. ChromaShader: RTL+仿真已完成，待 Quartus 编译 + 上板验证。`chroma` CLI 命令已注册 (第 22 个)。
