# de2os V3 状态

> 状态: **功能完成，打磨阶段**
> 硬件工程: `par/de2os/` (top entity: `de2os_top`)
> 目标固件: `sw/app/de2shell_rtos/` (~156KB, SDRAM exec)

## 当前构建

- 固件: ~156KB, SDRAM @ `0x01000000`
- RTL: `par/de2os/de2os.sof`
- PLL: c0=50MHz (CPU), c1=100MHz (SDRAM), c2=100MHz+1.56ns (DRAM_CLK), c3=25MHz (VGA)

## 板级验证 (2026-06-02)

| 模块 | 状态 | 备注 |
|------|------|------|
| SDRAM exec + bootloader | ✅ | 156KB 上传成功 |
| FreeRTOS 4 tasks | ✅ | uart_input/shell/active/status |
| UART shell | ✅ | 命令解析正常 |
| VGA text 80×30 | ✅ | 轻微斜线重影 (PLL c3 已改但仍可见) |
| PS/2 keyboard | ✅ | 主输入源 |
| hello / info | ✅ | ESC/F10 退出正常 |
| snake | ✅ | 1P/2P, F1 help, F10 quit |
| crypto bench | ✅ | AES 107.6x 加速 |
| expdemo 13 exp | ✅ | 全可用 |
| conway | ✅ (bug) | 功能正常, 花屏闪烁 |
| synth | ✅ (bug) | VGA/键盘正常, 无声音 |
| ntt | ⚠️ | CLI 进入正常, HW TIMEOUT status=0000 |
| ver / BuildInfo | ❌ | Load Access Fault |
| selfcheck | ✅ | 启动自检通过 |
| vgadump / vgamon | ✅ | |
| twm 像素模式 | ✅ | 30s 稳定 |
| 长稳 | ✅ | 7h38m 无崩溃 |

## 已知 Bug

### BUG-1: BuildInfo Load Access Fault (HIGH)

- **现象**: `ver` → Load Access Fault MTVAL=0xF0009000
- **根因**: `build_info_wb.vhd` 组合逻辑 ack, 与 XBUS register stage 不兼容
- **修复**: 添加 `clk_i` 端口, 改为寄存器 ack

### BUG-2: NTT HW TIMEOUT (HIGH)

- **现象**: `ntt`/`roundtrip` 报 HW TIMEOUT status=0000, 引擎从未启动
- **状态**: 地址链验证正确, 根因不明
- **文件**: `src/rtl/periph/ntt_sdf.vhd`, `sw/lib/ntt.h`

### BUG-3: Conway 花屏 (MEDIUM)

- **现象**: 细胞状态切换时全屏闪烁
- **根因**: 逐行局部刷新不足, 空格切换调用完整 draw_grid()
- **修复方向**: 逐格刷新
- **附**: random seed 固定 0xDEAD (应改用 TRNG)

### BUG-4: Snake 边框覆盖 HUD (LOW)

- **现象**: draw_border() 覆盖 HUD 行模式文字
- **修复方向**: 调整边框或 HUD 坐标

### BUG-5: Synth 无声音 (HARDWARE)

- **现象**: VGA/键盘正常, WM8731 无输出
- **状态**: 软件驱动和 VHDL 状态机正确, 问题在 I2C/I2S/CODEC 硬件层

## 外设板级状态

| 外设 | RTL | C driver | 上板 | 备注 |
|------|-----|----------|------|------|
| sdram_ctrl | ✅ | ✅ | ✅ | 128MB, burst, async FIFO CDC |
| vga_text_terminal | ✅ | ✅ | ✅ | 80×30 text + 640×480 RGB565 pixel |
| ps2_controller | ✅ | ✅ | ✅ | scancode + IRQ |
| lcd_wb | ✅ | ✅ | ✅ | HD44780 16×2 |
| ir_nec_wb | ✅ | ✅ | ✅ | NEC decoder |
| build_info_wb | ✅ | ✅ | ❌ | BUG-1: Load Access Fault |
| ntt_sdf | ✅ | ✅ | ⚠️ | BUG-2: TIMEOUT |
| expdemo_wb | ✅ | ✅ | ✅ | 13 experiments |
| conway_engine | ✅ | ✅ | ✅ | BUG-3: flickering |
| synth_engine | ✅ | ✅ | ✅ | BUG-5: no audio |
| gpu_2d | ✅ | ✅ | ✅ | FILL rect burst-write |
| chroma_shader | ✅ | ✅ | N/A | excluded from build |

## CLI 命令 (18 + help)

| 命令 | 程序 | 说明 |
|------|------|------|
| hello | prog_hello | LED chaser |
| crypto | prog_crypto | AES/SHA/SM4 bench |
| ps2 | prog_ps2 | PS/2 keyboard test |
| snake | prog_snake | Snake 1P/2P |
| conway | prog_conway | Conway HW 64×25 |
| info | prog_info | System dashboard |
| riscvasm | prog_monitor | RISC-V monitor |
| expdemo | prog_demo | 13 course labs |
| twm | prog_twm | Tiling window mgr |
| ntt | prog_ntt | NTT accelerator |
| synth | prog_synth | Audio synth |
| selfcheck | — | Board self-test (boot) |
| stats | — | Tasks + CPU + heap |
| ver | — | Version (BUG-1) |
| clear | — | Clear screen |
| pxtest | — | VGA pixel diag |
| vgadump | — | Dump VGA to UART |
| vgamon | — | Periodic VGA dump |

所有交互程序: F1=help, F10=quit to shell.

## 历史里程碑

- **2026-05-21**: NEORV32 first boot on DE2-115
- **2026-05-22**: SDRAM exec baseline, UART shell
- **2026-05-24**: FreeRTOS 4 tasks, VGA text 80×30
- **2026-05-29**: All RTL peripherals integrated (ntt/conway/synth/expdemo)
- **2026-05-30**: PS/2 TUI, Snake 2P, crypto viz
- **2026-06-01**: GPU 2D, VGA PLL fix, TWM pixel mode on monitor
- **2026-06-02**: Full board test, 5 bugs found, 7h38m stability verified
