# de2os V3 状态

> 状态: **功能完成，打磨阶段**
> 硬件工程: `par/de2os/` (top entity: `de2os_top`)
> 目标固件: `sw/app/de2shell_rtos/` (~212KB, SDRAM exec)

## 当前构建

- 固件: ~212KB, SDRAM @ `0x01000000`
- RTL: `par/de2os/de2os.sof`
- PLL: c0=50MHz (CPU), c1=100MHz (SDRAM), c2=100MHz+1.56ns (DRAM_CLK), c3=25MHz (VGA), altpll_audio=18MHz (WM8731 MCLK)

## 板级验证 (2026-06-03, 21:00 更新)

| 模块 | 状态 | 备注 |
|------|------|------|
| SDRAM exec + bootloader | ✅ | 212KB 上传成功 |
| FreeRTOS 4 tasks | ✅ | uart_input/shell/active/status |
| UART shell | ✅ | 命令解析正常 |
| VGA text 80×30 | ✅ | 轻微斜线重影 (PLL c3 已改但仍可见) |
| PS/2 keyboard | ✅ | 主输入源 |
| hello / info | ✅ | ESC 退出正常 |
| snake | ✅ | 功能正常, ESC 退出正常 |
| crypto bench | ✅ | AES 107.6x 加速 |
| expdemo 13 exp | ✅ | 全可用 |
| conway | ✅ | 功能正常, TRNG seed, 逐格刷新 |
| ver / BuildInfo | ✅ | 硬件/软件版本正常显示 |
| selfcheck | ✅ | 启动自检通过 |
| vgadump / vgamon | ✅ | |
| cryptoviz | ✅ | AES-128 step-through 可视化, pixel mode, FIPS 197 测试向量 |
| pforth | ✅ | pForth 解释器, `1 2 + .` → `3 OK`, ESC 退出正常 |
| twm 像素模式 | ✅ | Tiling window mgr, serial 命令正常, ESC 退出正常 |
| synth | ⬜ | HW 模块已从综合移除, 命令显示 "disabled" |
| ntt | ⬜ | HW 模块已从综合移除, 使用 SW NTT (~0.4ms) |
| 长稳 | ✅ | 7h38m 无崩溃 |

## 本次变更 (2026-06-03, session 4)

### NTT / Synth HW 从综合移除

- `ntt_sdf.vhd` 和 `synth_engine.vhd` 从 Quartus 工程文件注释掉
- `de2os_top.vhd` 中 NTT 和 Synth 实例注释掉 (端口和信号保留)
- NTT 程序改为纯 SW 实现 (~0.4ms, 20000 cycles @50MHz)
- Synth 命令改为 "disabled" 提示
- 活跃外设: 12 → 10, README / promo / 状态文档同步更新

## 本次变更 (2026-06-03, session 3)

### NTT 深度调试

- Barrett off-by-one 修复: `prod_mu(35 downto 23)` → `prod_mu(36 downto 24)` (shift 24, not 23)
- Quartus 编译通过 (0 errors, 290 warnings), SOF 烧录成功
- 新增 `verify` 命令: 全 256 元素 HW vs expected 对比
- 新增 `bfly` 命令: VHDL butterfly C 仿真 (delta input → all-1s PASS)
- Python 穷举验证: Barrett 1100 万组合 0 error, 地址计算 0 overflow
- **结论**: C bfly 仿真正确, Barrett 数学正确, 地址计算正确, 但 HW NTT 仍输出错误
  - roundtrip PASS (但检查太弱, 只测 element[0]!=0)
  - NTT(delta) 应为 all-1s, 实际 255/256 错误
  - 疑似 Quartus 综合问题: function 在 clocked process 中的行为
  - 待 QuestaSim testbench 或参考开源实现重写

### 上板验证通过

- **pforth**: 启动正常, `1 2 + .` → `3 OK`, ESC 退出正常
- **twm**: 启动正常, serial 命令显示, ESC 退出正常
- **snake**: 功能正常 (用户确认无问题), ESC 退出正常
- **synth**: 启动正常, ESC 退出正常 (pixel mode 无串口 echo, 需 VGA+音频验收)

### 文件变更

| 文件 | 变更 |
|------|------|
| `src/rtl/periph/ntt_sdf.vhd` | Barrett shift fix: >>24 (was >>23) |
| `sw/lib/ntt.c` | +forward decl, +verify cmd, +bfly help fix |

### 验收步骤

#### NTT Barrett RTL 重编译 ✅
- [x] Quartus 编译通过 (0 errors, 290 warnings, 49:30)
- [x] SOF 烧录成功
- [x] 固件上传成功 (~212KB)
- [x] `ntt` 程序启动正常, 不再 TIMEOUT
- [x] `diag` → bus OK, engine done (1032 cycles)
- [x] `bfly` → ALL-1s PASS, SW ref PASS, MATCH
- [ ] `verify` → FAIL (255/256 mismatch), 根因待查

#### pforth 上板 ✅
- [x] `pforth` 启动正常, 显示 pForth V2.1
- [x] `1 2 + .` → `3 OK`
- [x] ESC 退出正常

#### twm 上板 ✅
- [x] `twm` 启动正常, 显示命令列表
- [x] ESC 退出正常

#### synth 上板 🟡
- [x] `synth` 启动正常, ESC 退出正常
- [ ] 不按键 → 应完全静音 (BUG-5a)
- [ ] 松开键 → 应立即停止 (BUG-5b)
- [ ] ↑/↓ 音量键 (BUG-5c)

#### snake 上板 ✅
- [x] 功能正常 (用户确认)

## 已知 Bug

### BUG-1: BuildInfo Load Access Fault (FIXED 2026-06-02)

- **修复**: 添加 `clk_i` 端口, 改为寄存器 ack

### BUG-2: Conway 花屏 (FIXED 2026-06-02)

- **修复**: TRNG seed + 逐格刷新 + partial refresh

### BUG-3: NTT HW TIMEOUT (FIXED, 但计算结果仍错误) — HW 已移除

- **已修**: Stage 0 比特反转 + Stage 0 twiddle + Read mux stb 竞争 (2026-06-02)
- **已修**: Barrett off-by-one shift (2026-06-03)
- **剩余问题**: HW NTT 输出 255/256 元素错误, 根因未知
  - C bfly 仿真: all-1s PASS (算法正确)
  - Python 穷举: Barrett 0 error (数学正确)
  - 地址计算: 0 overflow (寻址正确)
  - roundtrip: PASS (但验证太弱)
  - 疑似 Quartus 对 VHDL function 在 clocked process 的综合问题
- **文件**: `src/rtl/periph/ntt_sdf.vhd`

### BUG-5: Synth 音频子问题 (待物理验收) — HW 已移除

- **已修 SW**: `synth.c` mute + note_off + volume ↑/↓
- **已修 RTL**: `synth_engine.vhd` auto-mute (已编译部署)
- **待验收**: 5a 背景音 / 5b 释放不停止 / 5c 音量键

## 外设板级状态

| 外设 | RTL | C driver | 上板 | 备注 |
|------|-----|----------|------|------|
| sdram_ctrl | ✅ | ✅ | ✅ | 128MB, burst, async FIFO CDC |
| vga_text_terminal | ✅ | ✅ | ✅ | 80×30 text + 640×480 RGB565 pixel |
| ps2_controller | ✅ | ✅ | ✅ | scancode + IRQ |
| lcd_wb | ✅ | ✅ | ✅ | HD44780 16×2 |
| ir_nec_wb | ✅ | ✅ | ✅ | NEC decoder |
| build_info_wb | ✅ | ✅ | ✅ | 版本信息正常 |
| ntt_sdf | ⬜ | ✅ | ⬜ | HW 已从综合移除, SW NTT 替代 |
| expdemo_wb | ✅ | ✅ | ✅ | 13 experiments |
| conway_engine | ✅ | ✅ | ✅ | TRNG seed, 逐格刷新 |
| synth_engine | ⬜ | ⬜ | ⬜ | HW 已从综合移除, 命令已禁用 |
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
| ntt | prog_ntt | NTT (SW only, HW disabled) |
| ~~synth~~ | — | Audio synth (disabled) |
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
- **2026-06-03**: BUG-1/2/3 修复, Barrett fix, cryptoviz/pforth/twm/snake 上板验证通过, 本地 SDL2 构建, V2 残余清理, NTT/synth HW 从综合移除 (10 active 外设)

## 待办 (按优先级)

1. ~~**NTT 根因排查**: HW NTT 计算错误, 需要 QuestaSim testbench 或参考开源重写~~ (已移除 HW, SW NTT 替代)
2. ~~**Synth 物理验收**: BUG-5a/5b/5c — 需插耳机/音箱, 按键测试~~ (已移除 HW)
3. **V3P8 TWM 刷新优化**: 见 `doc/phases/v3p8a.md`，P0 起步 (GPU 路由所有矩形填充)
4. **doc/promo**: slides.html 占位图需替换为实际截图
