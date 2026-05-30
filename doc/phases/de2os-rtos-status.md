# de2os FreeRTOS 集成状态

> 日期: 2026-05-30
> 状态: 软件编译通过，Quartus RTL 编译通过 (timing clean)，待上板验证
> 更新: 2026-05-30 — Exp6/7 VGA 测试图案集成 + I2C SDA 三态修复 + Exp8/10 重新接入; 13 实验全可用
> 硬件工程: `par/de2os/` (top entity: `de2os_top`)
> 目标固件: `sw/app/de2shell_rtos/`

## 当前结论

`de2os` 已完成软件编译和 Quartus RTL 编译的闭环。当前构建产物：

- 固件: `text=140456  data=1856  bss=81504  total=223816` (~142KB, +synth pending rebuild)
- RTL: `par/de2os/de2os.sof` (2026-05-29 15:38)
- Quartus: 0 errors, 271 warnings, all timing constraints met
  - Worst setup slack: +2.394 ns
  - Worst hold slack: +0.153 ns
  - LEs: 71,299/114,480 (62%), 31 EMUL, 592KB mem, 1 PLL

当前主瓶颈：**上板验证**。板子在队友手中。

## 已完成

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
- **注意: VGA 像素模式从未在物理显示器上成功显示过**

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
| snake | prog_snake | Snake game (全屏 78x27 + CP437 + vblank) |
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

## 当前剩余问题

### P0. VGA 像素模式从未成功显示 (最高优先级)

这是当前最关键的未解决问题。可能的原因：

1. VGA 信号路径问题 (sync/blank 信号未正确连接)
2. SDRAM 帧缓冲区读取路径问题 (VGA fetch FSM 或带宽)
3. VGA 输出 mux 问题 (text/pixel 切换)

诊断计划:
- `pxtest` 命令 Phase 1: test pattern 模式 (绕过 SDRAM) → 如果能看到色条 → 信号路径 OK，问题在 SDRAM
- `pxtest` Phase 3-4: SDRAM 模式 + debug 寄存器 → 定位具体失败点
- 如果 test pattern 都不显示 → VGA signal path 问题

### P1. 上板验证

所有以下项目需要上板确认：

- [ ] bootloader 上传 + SDRAM 执行
- [ ] FreeRTOS 4 任务调度正常
- [ ] shell PS/2 + UART 双路输入
- [ ] crypto bench (TRNG 修复后不再卡死)
- [ ] twm 进入/退出正常 (PS/2 修复后不再卡死)
- [ ] conwayhw / ponghw / ntt 基本功能
- [ ] pxtest 诊断 VGA 像素模式
- [ ] ExpDemo 13 个实验 (含 Exp6/7 VGA 测试图案)
- [ ] I2C SDA 三态修复后 audio synth 初始化

### P2. PS/2 目前主要是 ASCII 路径

方向键、功能键、组合键不一定完整穿透到 GUI。如果后面要让 GUI 的键盘体验完整，最好改成 richer event。

### P3. 无双缓冲

像素模式仍是单 framebuffer。理论上会有撕裂风险，但这不是当前启动阻塞项。

### P4. Audio synth RTL+C 均已完成，待上板验证

RTL + C 驱动均已完成 (synth_engine @ s11, synth.c CLI)。待固件重编译 + 上板验证:
1. I2C 配置 WM8731 → I2S 输出 → 耳机可听
2. PS/2 键盘弹奏测试

## 下一步

1. **板子到手后立即执行**:
   - `./run/deploy_de2shell_rtos.sh full` — 烧录新 RTL + 上传新固件
   - 运行 `pxtest` 诊断 VGA 像素模式
   - 验证 crypto/twm/conwayhw/ponghw/ntt/synth 基本功能
2. 根据 pxtest 结果决定 VGA 像素模式的修复方案
3. ChromaShader: RTL+仿真已完成，待 Quartus 编译 + 上板验证。`chroma` CLI 命令已注册 (第 22 个)。
