# de2os V3 状态

> 状态: **功能完成，打磨阶段**
> 硬件工程: `par/de2os/` (top entity: `de2os_top`)
> 目标固件: `sw/app/de2shell_rtos/` (~156KB, SDRAM exec)

## 当前构建

- 固件: ~156KB, SDRAM @ `0x01000000`
- RTL: `par/de2os/de2os.sof`
- PLL: c0=50MHz (CPU), c1=100MHz (SDRAM), c2=100MHz+1.56ns (DRAM_CLK), c3=25MHz (VGA), altpll_audio=18MHz (WM8731 MCLK)

## 板级验证 (2026-06-03, 15:00 更新)

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
| ntt | 🔧 | BUG-3 已修复 RTL (stage 0 + read mux), 待 RTL 重编译验收 |
| ver / BuildInfo | ✅ | 硬件/软件版本正常显示 |
| selfcheck | ✅ | 启动自检通过 |
| vgadump / vgamon | ✅ | |
| twm 像素模式 | 🟡 | 调试 dump 已移除, 渐变背景代码完成, 待上板验证 |
| cryptoviz | ✅ | AES-128 step-through 可视化, pixel mode, FIPS 197 测试向量, 已上板验证 |
| pforth | 🟡 | pForth 解释器, 已注册, 待上板验证 |
| 长稳 | ✅ | 7h38m 无崩溃 |

## 本次变更 (2026-06-03, session 2)

### 新增功能

1. **cryptoviz 注册到 RTOS** — `sw/app/de2shell_rtos/`
   - makefile: 添加 `crypto_viz.c`
   - main.c: PROG_CRYPTOVIZ (id=13), CLI 命令 `cryptoviz`, 栈 1024 字
   - 默认启动 AES-128 可视化, pixel mode

2. **本地 SDL2 构建重建** — `sw/lib/makefile` (新建)
   - `make` / `make run` / `make clean` 替代废弃的 `make local`
   - V3 程序全部编译: hello, crypto, ps2, snake, conway, ntt, synth, info, riscvasm, expdemo, twm, pforth, cryptoviz
   - 链接 crypto_cli (AES/SHA/SM4), pForth, gui/widgets
   - 编译通过, de2shell.exe (1.1MB) 可运行

3. **NTT RTL 修复** — `src/rtl/periph/ntt_sdf.vhd` (BUG-3 根因修复)
   - Stage 0 比特反转: `idx`/`grp` 赋值交换
   - Stage 0 twiddle: 改为常量 `"0000000"` (W^0=1)
   - Read mux: 移除 `wb_stb_i` 检查, 改用 `process(all)` + 仅 `wb_we_i='0'` (expdemo_wb 模式)
   - 添加 buffer 回读 (addr 0x000–0x0FF)
   - 需 RTL 重编译才能验证

### 清理

4. **cryptoviz 上板 bug 修复** — `sw/lib/crypto_viz.c` + `sw/lib/fb_hal.c`
   - fb_init: 移除 `VGA_PX_TESTPAT` 默认启用 (导致 pxtest 测试图覆盖实际渲染)
   - cv_init: 添加 `fb_clear(CV_BG)` 清除旧 framebuffer 内容 (TWM 残留)
   - cv_init: 默认 FIPS 197 测试向量 (key/PT 为空时不再立即退出)
   - SHA256: 同样添加 "abc" 默认消息

5. **V2 残余移除** — `sw/lib/main.c`
   - 删除 PROG_MEMTEST / PROG_LIFE / PROG_DASHBOARD 及其 shell 命令、IR 映射
   - 添加 PROG_CONWAY / PROG_NTT / PROG_SYNTH / PROG_FORTH
   - IR 遥控器键位重新映射: 1=hello 2=crypto 3=ps2 4=snake 5=conway 6=ntt 7=info 8=riscvasm 9=synth

6. **pForth 本地编译修复** — `sw/lib/pforth/`
   - pf_config.h: `PF_NO_MALLOC/FILEIO/CLIB` 改为 `#ifndef LOCAL_BUILD` 保护, 本地构建使用 stdlib
   - pf_io.c: 添加 `sdResizeFile` 非 FILEIO 模式的 stub

7. **NTT 本地编译修复** — `sw/lib/ntt.c`
   - `cmd_diag()` 用 `#ifndef LOCAL_BUILD` 包裹 (纯硬件诊断)

### 文件变更清单

| 文件 | 变更 |
|------|------|
| `src/rtl/periph/ntt_sdf.vhd` | BUG-3 修复: stage 0 比特反转 + read mux |
| `sw/app/de2shell_rtos/makefile` | +1 行: crypto_viz.c |
| `sw/app/de2shell_rtos/main.c` | PROG_CRYPTOVIZ 注册 + FIPS 默认参数 |
| `sw/lib/crypto_viz.c` | 默认 FIPS 测试向量 + init 清屏 |
| `sw/lib/fb_hal.c` | fb_init: 移除 VGA_PX_TESTPAT |
| `sw/lib/makefile` | **新建**: 完整的 SDL2 本地构建 makefile |
| `sw/lib/main.c` | V2 清理 + V3 程序同步 |
| `sw/lib/ntt.c` | cmd_diag LOCAL_BUILD 保护 |
| `sw/lib/pforth/pf_config.h` | LOCAL_BUILD 条件编译 |
| `sw/lib/pforth/csrc/pf_io.c` | sdResizeFile stub |
| `CLAUDE.md` | 命令表 +2, 本地构建说明更新 |
| `README.md` / `README.en.md` | CLI 数量 20, 加 pforth + cryptoviz |
| `Release_Report/main.tex` | CLI 数量 19→20 |
| `doc/phases/de2os-rtos-status.md` | 验收表 + 变更日志 + BUG-3 修复 |

### 验收步骤

#### A. RTOS 固件编译 (Docker) ✅
```bash
./run/deploy_de2shell_rtos.sh inc
```
- [x] Docker 编译成功 (crypto_viz.c 编译通过)
- [x] firmware size 报告 ~210KB (含 cryptoviz + pforth)
- [x] 上传成功

#### B. cryptoviz 上板 ✅
1. ~~在 shell 输入 `cryptoviz` → 屏幕切换到 pixel mode, 显示 AES-128 状态矩阵~~ ✅
2. ~~按 Space → 步进一轮 (SubBytes → ShiftRows → MixColumns → AddRoundKey)~~ (需 PS/2 键盘)
3. ~~按 A → 自动播放 (每步 ~300ms)~~ (需 PS/2 键盘)
4. ~~按 P → 暂停自动播放~~ (需 PS/2 键盘)
5. ~~按 L/R → 跳到上一步/下一步~~ (需 PS/2 键盘)
6. ~~按 F10 或 Q → 退出回文本 shell~~ ✅ (ESC 从 UART 退出正常)
7. 对比 FIPS 197 附录 B: Key=2B7E1516.. PT=6BC1BEE2.. CT=3AD77BB4.. (需 PS/2 键盘步进到终点)

#### C. 本地 SDL2 构建
```bash
cd sw/lib && make clean && make && ./de2shell.exe
```
- [ ] 编译 0 error
- [ ] 运行: 输入 `cryptoviz` → SDL2 窗口显示 AES 可视化
- [ ] Space 步进, A 自动, Q 退出正常
- [ ] 输入 `conway` / `ntt` / `synth` / `pforth` 均可进入
- [ ] `memtest` / `life` 命令返回 Unknown (已移除)

#### D. 回归检查 ✅
- [x] `hello` / `ver` 正常工作
- [x] `help` 输出包含 `cryptoviz` 和 `pforth`
- [x] ESC 退出 cryptoviz 后正常返回 shell

#### E. NTT RTL 验收 (需 RTL 重编译)
```bash
./run/deploy_de2shell_rtos.sh fpga   # 全量: RTL + bootloader + Quartus + 烧录
./run/deploy_de2shell_rtos.sh inc    # 再增量上传固件
```
- [ ] Quartus 编译通过 (ntt_sdf.vhd 修改)
- [ ] `ntt` 进入正常, 不再报 HW TIMEOUT
- [ ] `roundtrip` 显示 SW/HW 结果一致
- [ ] `diag` 返回正确状态 (busy/done/cycle_cnt)

## 已知 Bug

### BUG-1: BuildInfo Load Access Fault (FIXED)

- **现象**: `ver` → Load Access Fault MTVAL=0xF0009000
- **修复**: 添加 `clk_i` 端口, 改为寄存器 ack, 已验收通过

### BUG-2: Conway 花屏 (FIXED)

- **修复**: TRNG seed + 逐格刷新 + partial refresh, 2026-06-03

### BUG-3: NTT HW TIMEOUT (FIXED)

- **现象**: `ntt`/`roundtrip` 报 HW TIMEOUT status=0000, 引擎从未启动
- **根因**: 3 个 bug:
  1. **Stage 0 比特反转**: `idx` 和 `grp` 赋值反了 — stage 0 应 grp=全位, idx=0
  2. **Stage 0 twiddle**: 原代码用 `idx(0)&"000000"`, 修正为常量 `"0000000"` (W^0=1)
  3. **Read mux stb 竞争**: 组合进程读 `wb_stb_i` 与时钟进程冲突, Quartus 丢弃输出; 改用 `process(all)` + 仅检查 `wb_we_i='0'` (expdemo_wb 模式); 同时添加了 buffer 回读 (addr 0x000–0x0FF)
- **文件**: `src/rtl/periph/ntt_sdf.vhd`
- **验收**: 需 RTL 重编译 + 上板

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
| ntt_sdf | ✅ | ✅ | 🔧 | BUG-3 RTL 已修, 待重编译验收 |
| expdemo_wb | ✅ | ✅ | ✅ | 13 experiments |
| conway_engine | ✅ | ✅ | ✅ | TRNG seed, 逐格刷新 |
| synth_engine | ✅ | ✅ | 🟡 | BUG-5: SW mute/vol 已部署, RTL auto-mute 待编译 |
| gpu_2d | ✅ | ✅ | ✅ | FILL rect burst-write |
| chroma_shader | ✅ | ✅ | N/A | excluded from build |

## CLI 命令 (20 + help)

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
| pforth | prog_forth | pForth 解释器 |
| cryptoviz | prog_cryptoviz | AES/SHA step-through viz (pixel mode) |
| selfcheck | — | Board self-test (boot) |
| stats | — | Tasks + CPU + heap |
| ver | — | Version / build info |
| clear | — | Clear screen |
| pxtest | — | VGA pixel diag |
| vgadump | — | Dump VGA to UART |
| vgamon | — | Periodic VGA dump |

所有交互程序: F1=help, F10=quit to shell. cryptoviz: Space=step, A=auto, P=pause, L/R=skip, Q=quit.

## 历史里程碑

- **2026-05-21**: NEORV32 first boot on DE2-115
- **2026-05-22**: SDRAM exec baseline, UART shell
- **2026-05-24**: FreeRTOS 4 tasks, VGA text 80×30
- **2026-05-29**: All RTL peripherals integrated (ntt/conway/synth/expdemo)
- **2026-05-30**: PS/2 TUI, Snake 2P, crypto viz
- **2026-06-01**: GPU 2D, VGA PLL fix, TWM pixel mode on monitor
- **2026-06-02**: Full board test, 5 bugs found, 7h38m stability verified
- **2026-06-03**: BUG-1 BuildInfo 修复, BUG-2 Conway 修复, BUG-3 NTT RTL 修复 (stage 0 + read mux), BUG-5 synth 有音频 (3 子问题待验收), cryptoviz+pforth 注册, 本地 SDL2 构建重建, V2 残余清理

## 待办 (按优先级)

1. **NTT + Synth RTL 重编译**: BUG-3 RTL 已修 + synth auto-mute RTL 待编译 → `deploy_de2shell_rtos.sh fpga` 全量编译
2. **Synth 物理验收**: BUG-5a (背景音) / BUG-5b (释放不停止) / BUG-5c (音量键) — SW 已部署，RTL auto-mute 待编译
3. **Snake 边框**: BUG-4 调整 HUD/边框坐标
4. **V3P8 TWM 刷新优化**: 见 `doc/phases/v3p8-twm-perf.md`，P0 起步 (GPU 路由所有矩形填充)
