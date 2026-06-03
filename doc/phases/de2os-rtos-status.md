# de2os V3 状态

> 状态: **功能完成，打磨阶段**
> 硬件工程: `par/de2os/` (top entity: `de2os_top`)
> 目标固件: `sw/app/de2shell_rtos/` (~156KB, SDRAM exec)

## 当前构建

- 固件: ~156KB, SDRAM @ `0x01000000`
- RTL: `par/de2os/de2os.sof`
- PLL: c0=50MHz (CPU), c1=100MHz (SDRAM), c2=100MHz+1.56ns (DRAM_CLK), c3=25MHz (VGA), altpll_audio=18MHz (WM8731 MCLK)

## 板级验证 (2026-06-03, 04:00 AM 更新)

| 模块 | 状态 | 备注 |
|------|------|------|
| SDRAM exec + bootloader | ✅ | 156KB 上传成功 |
| FreeRTOS 4 tasks | ✅ | uart_input/shell/active/status |
| UART shell | ✅ | 命令解析正常 |
| VGA text 80×30 | ✅ | 轻微斜线重影 (PLL c3 已改但仍可见) |
| PS/2 keyboard | ✅ | 主输入源 |
| hello / info | ✅ | ESC/F10 退出正常 |
| snake | 🔧 | BUG-4: 边框覆盖 HUD, 修复中 |
| crypto bench | ✅ | AES 107.6x 加速 |
| expdemo 13 exp | ✅ | 全可用 |
| conway | ✅ | 功能正常, TRNG seed, 逐格刷新 |
| synth | 🔧 | **有音频**, 但需验收 3 个子问题 (见下方) |
| ntt | ⚠️ | CLI 进入正常, HW TIMEOUT status=0000 |
| ver / BuildInfo | ✅ | 硬件/软件版本正常显示 |
| selfcheck | ✅ | 启动自检通过 |
| vgadump / vgamon | ✅ | |
| twm 像素模式 | 🟡 | 调试 dump 已移除, 渐变背景代码完成, 待上板验证 |
| 长稳 | ✅ | 7h38m 无崩溃 |

## 已知 Bug

### BUG-1: BuildInfo Load Access Fault (FIXED)

- **现象**: `ver` → Load Access Fault MTVAL=0xF0009000
- **修复**: 添加 `clk_i` 端口, 改为寄存器 ack, 已验收通过

### BUG-2: Conway 花屏 (FIXED)

- **修复**: TRNG seed + 逐格刷新 + partial refresh, 2026-06-03

### BUG-3: NTT HW TIMEOUT (HIGH)

- **现象**: `ntt`/`roundtrip` 报 HW TIMEOUT status=0000, 引擎从未启动
- **状态**: 地址链验证正确, 根因不明
- **文件**: `src/rtl/periph/ntt_sdf.vhd`, `sw/lib/ntt.h`

### BUG-4: Snake 边框覆盖 HUD (LOW)

- **现象**: draw_border() 覆盖 HUD 行模式文字
- **修复方向**: 调整边框或 HUD 坐标

### BUG-5: Synth 音频 → 🔧 有输出，3 个子问题待验收

- **已修复 (2026-06-03 凌晨)**:
  1. 新增 `altpll_audio.vhd`: 50MHz → 18MHz PLL (VCO=900MHz)
  2. `wm8731_ctrl.vhd`: 寄存器对齐 Terasic (R4=0x08F8, R7=0x0E01, R8=0x1002)
  3. `synth_engine.vhd`: BCLK/LRCK 从 18MHz 生成 (div 6/div 188), AUD_XCK 直通 18MHz
  4. `i2s_tx.vhd`: 重写为 Terasic AUDIO_DAC.v 模式 (MSB-first, BCLK 下降沿)
- **串口验证**: ✅ Codec I2C ready, ✅ WB write ack, ✅ 程序不崩溃
- **物理验证**: ✅ 按键有音调输出

#### BUG-5a: 高频背景音 (MEDIUM)
- **现象**: 未按键时有高频背景噪音
- **已修 SW**: `synth.c` 添加 `update_mute()` — 无键按下时 mute=1 (已部署)
- **已修 RTL**: `synth_engine.vhd` 添加 auto-mute — any_note_active=0 时强制静音 (未编译)
- **验收**: 进入 synth 不按键 → 应完全静音

#### BUG-5b: 释放键不停止 (HIGH)
- **现象**: 松开键盘后音符持续，不会停止
- **已修 SW**: `note_off()` 调用 `update_mute()` 静音 + 写 TW=0 (已部署)
- **可能根因**: PS/2 release scancode 未被正确解码，或 WB 写 TW=0 后 DDS 相位未归零
- **验收**: 按住键播放 → 松开 → 应立即静音

#### BUG-5c: 音量键无反应 (LOW)
- **现象**: `-`/`=` 键无法调节音量，右上角音量条无变化
- **已修 SW**: 改用 ↑/↓ 箭头键调音量 (已部署)
- **验收**: 按 ↑ 音量增大（音量条变长），按 ↓ 音量减小

#### Synth 物理验收步骤

1. 插耳机/音箱到 DE2-115 **绿色音频口**
2. 运行 `synth` 命令
3. 不按键 → **应完全静音** (BUG-5a)
4. 按住 A 键 → 应听到 C4 音调
5. 松开 A 键 → **应立即停止** (BUG-5b)
6. 按 ↑/↓ 键 → **音量应变化**，右上角音量条显示 (BUG-5c)
7. 按 F1 查看帮助，F10 退出

## 外设板级状态

| 外设 | RTL | C driver | 上板 | 备注 |
|------|-----|----------|------|------|
| sdram_ctrl | ✅ | ✅ | ✅ | 128MB, burst, async FIFO CDC |
| vga_text_terminal | ✅ | ✅ | ✅ | 80×30 text + 640×480 RGB565 pixel |
| ps2_controller | ✅ | ✅ | ✅ | scancode + IRQ |
| lcd_wb | ✅ | ✅ | ✅ | HD44780 16×2 |
| ir_nec_wb | ✅ | ✅ | ✅ | NEC decoder |
| build_info_wb | ✅ | ✅ | ✅ | 版本信息正常 |
| ntt_sdf | ✅ | ✅ | ⚠️ | BUG-3: TIMEOUT |
| expdemo_wb | ✅ | ✅ | ✅ | 13 experiments |
| conway_engine | ✅ | ✅ | ✅ | TRNG seed, 逐格刷新 |
| synth_engine | ✅ | ✅ | 🟡 | BUG-5: SW mute/vol 已部署, RTL auto-mute 待编译 |
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
- **2026-06-03**: BUG-1 BuildInfo 修复, BUG-2 Conway 修复, BUG-5 synth 有音频 (3 子问题待验收), 软件静音+音量+读回已部署

## 待办 (按优先级)

1. **Synth 物理验收**: BUG-5a (背景音) / BUG-5b (释放不停止) / BUG-5c (音量键) — SW 已部署，RTL auto-mute 待编译
2. **TWM 上板验证**: 渐变背景 + 调试 dump 移除 — 固件已编译，待上传
3. **NTT HW TIMEOUT**: BUG-3 根因排查，与 synth RTL auto-mute 一起编译
4. **Snake 边框**: BUG-4 调整 HUD/边框坐标
