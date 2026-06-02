# de2os FreeRTOS 集成状态

> 日期: 2026-06-02
> 状态: **V3 功能完成，打磨阶段**
> 更新: 2026-06-02 — life.c 删除, conwayhw→conway 重命名, F1/F10 帮助系统统一, Conway 网格读取 VHDL 修复 (待 Quartus), snake 缓冲区溢出修复, synth F1 修复
> 硬件工程: `par/de2os/` (top entity: `de2os_top`)
> 目标固件: `sw/app/de2shell_rtos/`

## 当前结论

V3 功能开发完成，进入打磨/文档阶段。所有交互式程序已统一 F1/F10 操作逻辑。软件 Conway (life.c) 已删除，硬件 Conway (conway_hw.c) 接管。Conway VHDL 网格读取修复 + toggle_cell 需要重新编译 Quartus。

当前构建：
- 固件: ~156KB
- RTL: `par/de2os/de2os.sof` (已烧录)
- PLL: c0=50MHz, c1=100MHz, c2=100MHz(+1.56ns), c3=25MHz(VGA)

## 已完成

### 0. GPU 2D 加速器 + VGA PLL 修复 (2026-06-01)

详见 `doc/phases/phase6-gpu-2d.md`。

- **GPU 2D**: RTL (gpu_2d.vhd) + C 驱动 (gpu.h/gpu.c) + SDRAM burst-write 端口 + 总线集成 (s11 @ 0xF0015000)
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
- **2026-05-31: TWM 命令首次在物理显示器上显示像素模式内容！**

### 5. PS/2 已接入 RTOS 输入队列（主输入源）

- `t_uart_input()` 同时轮询 UART + PS/2 MMIO
- 排除机制: PROG_PS2 / PROG_TWM / PROG_SYNTH 的 PS/2 轮询由各自程序负责，不经过 t_uart_input

### 6. RTOS 版本的程序集已完成集成

所有程序已注册 CLI 命令，makefile 已同步：

| CLI 命令 | 程序 | 说明 |
|----------|------|------|
| hello | prog_hello | LED chaser |
| memtest | — | SDRAM diagnostic (built-in) |
| crypto | prog_crypto | AES/SHA/SM4 CLI + bench |
| ps2 (kbd) | prog_ps2 | PS/2 keyboard test |
| snake | prog_snake | Snake game (1P/2P, WASD+箭头, F1帮助, F10退出) |
| conway | prog_conway | Conway 硬件引擎 (64×25, F1帮助含规则, 空格切换, F10退出, +/-调速) |
| info | prog_info | System dashboard |
| monitor (riscvasm) | prog_monitor | Memory/register monitor |
| expdemo (demo) | prog_demo | 13 course labs (Exp1-13 全可用) |
| twm | prog_twm | Tiling window manager (像素模式 GUI) |
| ntt | prog_ntt | NTT 加速器 CLI |
| synth | prog_synth | Audio synth (PS/2 钢琴键盘, F1帮助, F10退出) |
| pxtest | — | VGA 像素模式诊断 (5-phase) |
| vgadump | — | VGA framebuffer dump |
| vgam | — | VGA mode query |
| stats | — | Task list + stack HWM |
| heapstat | — | Heap usage |
| cpustat | — | CPU usage per task |
| clear | — | Clear VGA screen |

**已删除的命令**: `life` (软件 Conway), `conwayhw` (重命名为 `conway`), `ponghw` (未集成), `chroma` (源码存在但排除编译)

### 7. C 驱动完成 (synth.c)

Audio synth C 驱动 (`sw/lib/synth.c`): 88 音符 tuning table, PS/2 双轨钢琴键盘映射, 3xOSC/DX7 模式切换, 预设加载, Tab/Caps/NumLock 八度切换, F1 帮助, F10/Q 退出静音。CLI 命令 `synth` 已注册。待固件重编译 + 上板验证。

### 8. RTL 外设已全部集成 (2026-05-29)

以下外设在 `de2os_top.vhd` 中已从 stub 升级为实际实例化：

| 外设 | 状态 | 说明 |
|------|------|------|
| ntt_sdf | 实例化 | Wishbone slave s4 @ 0xF000F000 |
| conway_engine | 实例化 | Wishbone slave s9 @ 0xF0011000 |
| INTC s7 | 修复 | ack loopback (不再挂死总线) |
| synth_engine | 实例化 | Wishbone slave s10 @ 0xF0012000, AUD/I2C pins |
| Exp6/7 VGA 适配器 | 实例化 | adapt_exp6/7 + vga_test_pattern, VGA 输出 mux |

### 9. F1/F10 统一帮助系统 (2026-06-02)

所有交互式程序统一操作逻辑：

| 按键 | 功能 |
|------|------|
| F1 | 切换帮助叠加层 (游戏暂停) |
| F10 | 帮助打开时关闭帮助；帮助关闭时退出到 shell |

**各游戏帮助内容**:

- **Snake**: 方向键/WASD移动, 空格/R重开, F1帮助, F10退出
- **Conway**: 方向键/WASD移动光标, 空格切换细胞, Enter运行/暂停, R随机, C清除, +/-调速(每秒代数), F1帮助(含B3/S23规则), F10退出
- **Synth**: Z-M音符, Tab/CapsLock八度, M切换3xOSC/DX7, F1帮助, F10/Q退出

**技术实现**: 每个程序维护 `help_open` 标志 + `draw_help()` 叠加层 + `redraw()` 全量重绘。`update()` 在 help_open 时跳过。

### 10. Conway 硬件加速 (2026-06-02)

- **VHDL 修复**: 网格从 80×25 缩减为 64×25 (2-word row read, ramstyle="logic")
- **VHDL 新增**: toggle_cell 命令 (cmd bit4, control bits[6:0]=col_idx)
- **C 驱动重写**: 2-word hw_read_row(), cell_bit() 辅助函数, F1 帮助叠加层 (含 B3/S23 规则)
- **命令重命名**: `conwayhw` → `conway`
- **显示布局**: 内容 C2–C65, R2–R26; 边框 C1/C66, R1/R27; HUD R0 左侧, RUN/STOP 右上角
- **调速**: +/- 调整每秒代数 (speed_ms)
- **待 Quartus 重编译** (VHDL 更改需要)

### 11. Bug 修复 (2026-06-02)

| 问题 | 修复 | 文件 |
|------|------|------|
| snake 缓冲区溢出 (MAX_SNAKE) | body shift 循环 clamped to len-1 | `snake.c` |
| synth F1 无反应 | input() 回调为空，添加 F1/F10/Q 处理 | `synth.c` |
| synth Q 绕过 help_open | Q 退出前检查 help_open | `synth.c` |
| conway 变量遮蔽 | default case 内 k 声明移除 | `conway_hw.c` |
| R29 光标冲突 | hw_cursor_sync() 钳位到 scroll_bottom | `vga_hal.c` |
| life/conwayhw 冗余 | 删除 life.c, 重命名 conwayhw→conway | `main.c`, makefile |

### 12. 历史Bug 修复 (2026-05-29/30)

| 问题 | 修复 | 文件 |
|------|------|------|
| crypto bench 卡死 | `trng_bytes()` 无 `trng_available()` 检查 → 无限 busy-loop | `crypto.c` |
| twm 卡死 | PS/2 竞争: t_uart_input 和 tiling_update 同时轮询 PS/2 MMIO | `main.c` 排除列表 |
| ntt.c NEORV32 编译失败 | `ntt_a[]` 仅在 LOCAL_BUILD 下声明，NEORV32 路径改用直接 MMIO | `ntt.c` |
| INTC 0xF000A000 访问挂死 | s7_ack_i = '0' → 总线无响应；改为 ack loopback | `de2os_top.vhd` |
| I2C SDA 总线竞争 | I2C_SDAT 从 out 改为 inout 三态缓冲 | `wm8731_ctrl.vhd` 等 |

### 13. PS/2 TUI 增强 + Snake 2P + 全局 Fn 键 (2026-05-30)

PS/2 虚拟键码系统：22 个 VK 常量 (F1-F12, 方向键, 导航键)，门控条件修改使非 ASCII 键到达程序。Snake 支持双人模式 (WASD + 方向键)。

## 当前剩余问题

### P0. VGA 像素模式 (2026-06-01 更新 — 数据通路已验证，显示质量待修)

- BUG-1: 文本模式 UART TX 期间仍有斜线重影 (PLL c3 单路未解决)
- BUG-2: TWM 像素模式显示与修复前相同 (数据通路正确但显示质量差)
- 下一步: 双 PLL 输出 (c3=25MHz 0° + c4=25MHz -90°) 或调查 DAC 输出路由/去耦

### P1. 上板验证 (2026-06-02 更新)

- [x] bootloader 上传 + SDRAM 执行 — ✅ 156KB 固件上传成功
- [x] FreeRTOS 4 任务调度正常 — ✅ stats 显示 4 任务 + 栈 HWM 正常
- [x] shell UART 输入 — ✅ UART 输入到达 shell，命令解析正常
- [x] VGA 文本终端 80×30 显示 — ✅ vgadump 快照正常
- [x] help/stats/heapstat/cpustat/clear — ✅ UART+vgadump 验证通过
- [x] hello/info 交互式程序 — ✅ ESC 退出正常
- [x] twm 进入/像素模式显示 — ✅ 30 秒稳定运行
- [x] pxtest 诊断 VGA 像素模式 — ✅ SDRAM 回读 0 错误，burst read 正常
- [x] snake 游戏 — ✅ 验收通过 (F1帮助, 双人模式, 缓冲区修复)
- [x] ExpDemo 13 个实验 — ✅ 全可用
- [ ] conway 硬件 Conway — Quartus 重编译中 (64×25, ramstyle="logic", toggle_cell, F1含B3/S23规则, GPS调速)
- [ ] synth 音频合成 — 待上板验证 (I2C+I2S)
- [ ] crypto bench — 待测试
- [ ] ntt 加速器 — 待测试
- [ ] twm 画面质量 — 待用户肉眼验证
- [ ] VGA 文本模式重影 — 待修复

### P2. Quartus 重编译 (conway VHDL)

conway_engine.vhd 更改需要 Quartus 重编译：
1. 网格缩减 80→64 列, ramstyle="logic" (LE 寄存器替代 M9K)
2. 移除 addr 6 (cols 64-79) 读寄存器
3. toggle_cell 命令: cmd bit4, control bits[6:0]=col_idx

## 下一步

1. **Quartus 重编译**: conway VHDL 修改 → 烧录 → 验证 conway 空格切换 + 64列显示 + 随机填充
2. **验证 synth/ntt/crypto 基本功能**
3. **VGA 显示质量**: 文本模式重影 + 像素模式画面
4. **V3 最终文档**: 撰写项目总结文档
