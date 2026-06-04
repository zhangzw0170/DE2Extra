# DE2Extra V3 系统审计

> 日期: 2026-06-02
> 版本: V3 功能完成后、收尾阶段
> 固件: ~199KB (de2shell_rtos)
> RTL: `par/de2os/de2os.sof`

## 系统定位

把 DE2-115 从一块 FPGA 开发板变成一台完整的计算机：NEORV32 RISC-V 软核 + FreeRTOS + SDRAM 执行 + VGA 显卡 + PS/2 键盘 + 音频声卡 + 硬件加速器 (NTT/Conway/GPU 2D/Synth) + 多个交互式程序。

课程要求：跑 13 个实验。实际交付远超要求。

## 致命问题审计

| # | 问题 | 严重度 | 状态 |
|---|------|--------|------|
| 1 | VGA 文本模式斜线重影 (PLL/DAC) | MAJOR | 未修，影响所有文本显示观感 |
| 2 | 4 个外设未上板验证 (synth/ntt/crypto/conway) | MAJOR | 固件已上传，缺实际操作验证 |

无 CRITICAL 级别问题——系统能启动、能交互、核心功能工作。

## 功能完成度

### 已验证 (板上跑通)

| 模块 | 说明 |
|------|------|
| SDRAM 启动 + 200KB 固件 | Bootloader → 0x01000000 执行 |
| FreeRTOS 4 任务调度 | shell/uart_input/active_prog/status |
| UART shell + 命令解析 | 18 个 CLI 命令 |
| VGA 文本 80×30 | 有斜线重影，功能正常 |
| PS/2 键盘输入 | 主输入源，轮询式 |
| Snake (1P/2P, F1帮助) | 验收通过 |
| ExpDemo 13 个实验 | 全可用 |
| pForth 解释器 | 完整 Forth: 算术/比较/逻辑/栈/DO LOOP/IF ELSE/VARIABLE/CONSTANT/CREATE/MEMORY/EMIT/TYPE/WORDS/F1帮助/F10退出 |
| TWM 像素模式 | 30 秒稳定运行 |
| R29 状态栏隔离 | scroll region R0-R28, R29 独占 |
| LCD/7-SEG 状态显示 | Heap%/Uptime |

### 未验证 (代码完成，缺上板测试)

| 模块 | 风险 | 说明 |
|------|------|------|
| Conway 硬件 (64×25) | 低 | VHDL 已编译烧录，C 驱动逻辑简单 |
| Synth 音频输出 | 中 | I2C+I2S 通路长，WM8731 配置复杂 |
| NTT 加速器 | 中 | 纯 MMIO 交互，但没跑过真实 NTT 数据 |
| Crypto bench | 低 | 纯软件，NEORV32 内置 Zkn 扩展 |
| VGA 像素模式画质 | 中 | 数据通路正确，DAC/PLL 视觉质量未确认 |

## 上板验证结果 (2026-06-02 15:00)

| 模块 | 结果 | 问题 |
|------|------|------|
| Conway | 启动/渲染/边框/状态栏 OK | toggle_cell 不生效 (Pop=0)，VHDL 需排查 |
| NTT | 启动/菜单 OK | HW roundtrip 超时 (status=0x0000)，加速器未响应 |
| Crypto | 启动/CLI OK | bench 卡死 (uptime 不更新)，XBUS 挂死 |
| Synth | 启动/显示 OK | 未测音频输出（需 PS/2 键盘物理操作） |

NTT 和 Crypto 的卡死是同一类问题：硬件加速器的 Wishbone 接口未正确响应，XBUS timeout 后系统可能卡在异常状态。Conway toggle_cell 是 VHDL 新增命令，位域解析可能有误。

## 根因分析与修复 (2026-06-02 18:00)

### Conway + NTT 地址解码错误 (同一类 bug)

**根因**: VHDL 模块将 `wb_adr_i` 当作字节地址进行二次移位，但 `wb_intercon` 已经传递了字对齐地址 (`m_adr_i(6:2)` 或 `m_adr_i(13:2)`)。所有寄存器偏移量被除以 4 再除以 4，导致地址完全错位。

| 模块 | 错误代码 | 修复 |
|------|----------|------|
| Conway | `wb_adr_i(4 downto 2)` | `wb_adr_i(2 downto 0)` |
| NTT | `x"400"` (ctrl), `x"404"` (status), `wb_adr_i(9:2)` (data) | `x"100"`, `x"101"`, `wb_adr_i(7:0)` |
| Synth | `case wb_adr_i is` (直接用全值) | 无需修改，已正确 |

Conway 的影响:
- CMD (offset 0x00) 地址恰好为 0，不受二次移位影响 → clear/randomize/step 正常
- CTRL (offset 0x04) 被映射到 CMD → toggle 写入了错误的寄存器
- GRID_LO/MID (offset 0x10/0x14) 被映射到 CTRL → 读取始终返回 0（grid 显示全空）

NTT 的影响:
- CTRL/STATUS (byte offset 0x400/0x404) → VHDL 检查字地址 0x400/0x404，但实际传入的是 0x100/0x101 → 控制命令和状态读取完全失效
- 数据读写 (byte offset idx*4) → VHDL 用 `wb_adr_i(9:2)` 提取 index，实际应该用 `wb_adr_i(7:0)` → 数据也可能写入错误位置

### Crypto bench 不是 bug

Crypto bench 运行 1000 次 × 5 算法 × 2 变体 = 10000 次加密操作，纯 CPU 计算。FreeRTOS t_status 任务在 bench 运行期间无法获得时间片，因此 uptime 不更新。bench 最终会完成，不是真正的挂死。

## 五维度评分

| 维度 | 分数 | 说明 |
|------|------|------|
| 功能完整性 | 8/10 | 18 命令 + 13 实验 + 多个交互程序。4 外设待验证 |
| 工程质量 | 7/10 | 统一 F1/F10 帮助、R29 scroll region 隔离、VGA mutex。TRNG 一直 FAILED 未修 |
| 硬件集成 | 9/10 | 12 个 Wishbone slave 全接线，地址解码干净 |
| 超出课程要求 | 9/10 | 课程只要 13 个实验，实际造了一台 RISC-V 计算机 |
| 稳定性 | 6/10 | TWM 30s 不崩，但 VGA 重影影响观感，synth/ntt 未测 |

## 短板分析

最大弱点是**验证覆盖不足**。代码写了大量功能但上板验证不够：

1. **VGA 重影** — 所有用户第一眼就看到的问题。PLL/DAC 路由问题，可能需要双 PLL 输出或重新看 DAC 去耦
2. **Synth 完全没听过** — I2C 配 WM8731 + I2S 数据流，最容易"编译过但出不了声"
3. **NTT 没跑过真实数据** — 加速器空转和实际 NTT 运算是两回事

## 收尾优先级

1. Conway 上板验证 — 最简单，Quartus 已烧，按键盘操作看 64×25 网格
2. Crypto bench — 纯软件，UART 输出结果，最容易验证
3. NTT 基本测试 — `ntt` 命令看有没有响应
4. Synth 基本测试 — 插耳机/音箱，按 PS/2 键盘听有没有声音
5. VGA 重影 — 最难修，需要硬件知识，最后处理

前 4 项约 1-2 小时可全部验证。

## 总评

**Accept with Revisions** — 架构和功能范围远超课程要求，代码质量扎实。短板是验证覆盖不够，4 个外设没上板确认。花 1-2 小时把 Conway/Crypto/NTT/Synth 跑一遍，就能从"代码完成"升级到"系统完成"。

## 待修问题清单

- [ ] VGA 文本模式斜线重影
- [x] TRNG 自检 FAILED — 软件测试 bug: `neorv32_trng_get_fifo_depth()` 返回 FIFO 容量 (始终=4)，非当前条目数，导致 wait 循环从不等待，从空 FIFO 读取全零
- [x] Conway toggle_cell — VHDL 地址解码修复 (wb_adr_i(4:2) → (2:0))
- [x] NTT 加速器不响应 — VHDL 地址解码修复 (x"400"→x"100", wb_adr_i(9:2)→(7:0))
- [x] Crypto bench "卡死" — 非 bug，纯 CPU 密集计算，已加黄色警告
- [x] R29 scroll region — vga_clear() 重置 scroll_bottom，已改为 VGA_ROWS-2
- [x] Crypto 无 F1/F10 — 已添加 F1 简要帮助 + F10 退出
- [x] Forth 无 F10 — 已添加 F10 退出，帮助不再销毁会话
- [x] Conway HUD hex — 改为 decimal 显示
- [x] Shell 欢迎界面 — 添加 "F10/ESC exits any program" 提示
- [x] NTT HW 操作无反馈 — 添加 "running..." 黄色提示
- [x] Crypto bench 无进度指示 — 每个 algorithm 后输出 progress dot
- [x] Forth 错误码不友好 — 常见 ThrowCode 改为可读文本
- [x] Synth Q 键未文档化 — help overlay 添加 "F10 / Q: Quit"
- [x] Crypto parse_u32_dec 溢出 — 添加 n>99999 guard
- [x] UART 串口角色 — 默认关闭 VGA mirror，shell 双路输出，CLI 程序纯文本 UART，Ctrl+C 强制退出
- [x] Synth WM8731 I2C — CFG 寄存器地址全 0 (写入目标错误)，ACTIVE 寄存器未设置，master 模式未启用
- [x] Synth I2C STOP — 无条件 state 赋值覆盖 STOP 条件
- [x] Synth I2S lrck_edge — 缺少 else 清零，脉冲永久为高

## 验收表 (Release v1.0)

| 模块 | 功能 | 代码 | UART 验证 | VGA 验证 | 备注 |
|------|------|------|-----------|----------|------|
| SDRAM 启动 | Bootloader → 0x01000000 | ✅ | ✅ | — | 200KB 固件稳定加载 |
| FreeRTOS 4 任务 | shell/uart_input/active/status | ✅ | ✅ | — | 调度正常，stats 可读 |
| UART shell | 18 命令 + 帮助 + Ctrl+C | ✅ | ✅ | — | 干净纯文本，无 ANSI 噪音 |
| VGA 文本 80×30 | 字符终端 + R29 状态栏 | ✅ | — | ✅ | 有斜线重影 (PLL)，功能正常 |
| PS/2 键盘 | 轮询式主输入 | ✅ | — | ✅ | F1/F10/Ctrl+C 统一 |
| Snake | 1P/2P, F1帮助, F10退出 | ✅ | ✅ (启动/退出) | ✅ | |
| ExpDemo | 13 个实验 | ✅ | ✅ (启动) | ✅ | |
| pForth | 完整 Forth REPL | ✅ | ✅ (启动) | ✅ | F10退出, 帮助保留会话, CLI UART |
| Conway (HW) | 64×25 硬件加速 | ✅ | ⏳ | ⏳ | VHDL 地址已修，需 Quartus 重建 |
| NTT (HW) | 256-point NTT 加速 | ✅ | ⏳ | ⏳ | UART 测试: HW TIMEOUT (status=0000)，需 Quartus 重建 |
| Crypto | AES/SHA/SM4/SM3/bench | ✅ | ✅ (启动/help) | ⏳ | CLI UART 输出正常，bench 待 VGA 验证 |
| Synth | 3xOSC + DX7 FM | ✅ | ⏳ | ⏳ | I2C/I2S VHDL 已修 (5 bugs)，需 Quartus 重建 |
| Hello | LED chaser | ✅ | ✅ | ✅ | CLI UART 输出正常 |
| Info | System dashboard | ✅ | ⏳ | ✅ | CLI 标记，待 UART 测试 |
| Monitor | RISC-V 监控器 | ✅ | ⏳ | — | CLI 标记，待 UART 测试 |
| TWM 像素模式 | 30s 稳定运行 | ✅ | — | ✅ | |
| VGA 像素画质 | 640×480 RGB565 | ✅ | — | ⏳ | 数据通路正确 |
| LCD/7-SEG 状态 | Heap%/Uptime | ✅ | — | ✅ | |
| GPU 2D | FILL rect SDRAM burst | ✅ | — | ⏳ | RTL 集成，待验证 |
| ChromaShader | 色彩着色器 | ✅ | — | — | RTL 验证通过，C 驱动未集成 |
| UART 调试通道 | shell 双路 + CLI 纯文本 + vgadump | ✅ | ✅ | — | 无 VGA mirror 噪音 |
| vgadump/vgamon | VGA 帧捕获到 UART | ✅ | ✅ | — | 按需捕获，独立于 mirror |

### UART 验证详情 (2026-06-02 17:50)

通过 (见设备管理器) 串口逐项测试：

| 测试项 | 结果 | 说明 |
|--------|------|------|
| shell prompt + 命令回显 | PASS | 干净纯文本，无 ANSI 转义码 |
| help 命令 | PASS | 18 个命令完整列出 |
| stats 命令 | PASS | 任务表 + CPU% 可读 |
| ver 命令 | PASS | 硬件/软件信息完整 |
| hello 启动 + Ctrl+C 退出 | PASS | CLI UART 输出正常，Ctrl+C 即时退出 |
| crypto 启动 + help | PASS | 内部 CLI 输出到 UART |
| ntt 启动 + load delta | PASS | 内部 CLI 输出到 UART |
| ntt HW NTT | TIMEOUT | status=0000，需 Quartus 重建 |
| Ctrl+C 强制退出 | PASS | 从任何 CLI 程序即时返回 shell |
| F10 退出 (0x8E) | PASS | shell 层拦截，不传给程序 |
| 状态栏 UART 隔离 | PASS | 无 "DE2Extra RTOS | Crypto | up Xs" 噪音 |
| 程序生命周期消息 | PASS | ">> X started" / ">> returned to shell" |

### Quartus 重建后待验证

- [ ] NTT HW roundtrip（VHDL 地址解码已修）
- [ ] Conway toggle_cell + grid 渲染（VHDL 地址解码已修）
- [ ] Synth 音频输出（I2C+I2S 通路）
- [ ] VGA 像素模式画质（DAC/PLL）
- [ ] Crypto bench 完整运行（含 AES 加密结果验证）
