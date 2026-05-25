# Phase 3: 集成 + 多模块整合

> 总纲: `../implementation_plan.md`
> 状态: 2026-05-24 — shell 已上板跑通，SDRAM 控制器稳定(memtest PASS)，SDL2 HAL + NTT 加速器 VHDL 已完成
>
> **de2shell 程序注册表 (2026-05-24 更新)**:
>
> | 命令 | 程序 | 来源 | 说明 |
> |------|------|------|------|
> | `hello` | prog_hello | Phase 0 | LED 跑马灯 + HEX/秒计数器演示 |
> | `memtest` | prog_memtest | Phase 1 | SDRAM 4 项自检 (walking-1s ×2, checkerboard, addr-as-data) |
> | `crypto` | prog_crypto | Phase 2a | AES/SHA/SM4/SM3/TRNG 密码学终端 |
> | `snake` | prog_snake | Phase 3 | 贪吃蛇 (40×20) |
> | `life` | prog_life | Phase 2b | Conway 生命游戏 |
> | `dash` | prog_dashboard | Phase 3 | 系统仪表盘 |
> | `info` | prog_info | Phase 3 | 系统信息 |
> | `ps2` | prog_ps2 | Phase 2b | PS/2 键盘扫描码测试 |
> | `monitor` | prog_monitor | Phase 3 | 系统监控 (GPIO/UART 轮询) |
> | `expdemo` | prog_expdemo | ExpDemo | 硬件实验多路复用 (11 实验) |
> | `cls` | — | — | 清屏 |
> | `quit` | — | — | 回到 shell |
>
> **IR 遥控映射**: `1-9` 按 shell 内部频道号对应 hello/memtest/crypto/ps2/snake/life/dash/info/monitor，`A=expdemo`，`CH+/CH-` 顺序切换

## 本阶段概述

统一 Shell (`de2shell`) 作为主程序，UART/VGA 双输出。所有已验证的实验模块通过 CLI 命令或 IR 遥控器切换运行；当前新增 `board_status` 作为 LCD/HEX/LED 的统一状态编码层。

---

## 验收表

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| 1 | Unified Shell 框架 | 命令解析 + 程序调度 + VGA HAL 双模式编译 | ☑ (本地+Docker) |
| 2 | VGA 终端集成 | CPU 通过 XBUS 写 VGA buffer, 彩色显示 | 🟡 (HAL 已就位, 总线基础已具备) |
| 3 | IR 遥控器输入 | NEC 解码 → 程序切换 | ☑ (ir_nec_decoder.vhd + handle_ir) |
| 4 | 状态栏 | 底行常驻显示当前频道名，右侧显示 uptime | ☑ (代码完成) |
| 5 | 实验 CLI 程序集 | expdemo 通过 shell 命令运行 (11 实验多路复用) | ☑ (expdemo_wb.vhd + de2shell expdemo 命令) |
| 6 | C 游戏 | Snake + Conway Life | ☑ (独立编译通过, text=4400+4876B) |
| 7 | 密码学终端 | AES/SHA/SM4/SM3 CLI | ☑ (Phase 2a 独立编译) |
| 8 | F1/F2 双页 | VGA 硬件双页缓冲 | ☑ (vga_text_terminal.vhd) |
| 9 | 已验收模块挂载 | 当前 shell 已集成 hello/memtest/crypto/ps2/snake/life/dash/info/monitor/expdemo | ☑ |
| 10 | 板级状态统一层 | LCD/HEX/LED 通过 `board_status` 统一声明与接管 | 🟡 (代码完成，待下一次上板确认) |
| 11 | Docker 编译 | 所有 C 程序交叉编译通过, text < 64KB IMEM | 🟡 (本轮编译被中断，待继续) |

---

## 13 实验覆盖状态

| # | 实验 | VGA 展示 | 接入方式 |
|---|---|---|---|
| 1 | 3-8 译码器 | ✅ SW→LEDR 实时映射 | ExpDemo 通道 |
| 2 | 彩灯显示 | ✅ LED 9 模式 | ExpDemo 通道 |
| 3 | 七段管+电子钟 | ✅ BCD 时间 | ExpDemo 通道 |
| 4 | 双口 RAM | ✅ 操作说明+状态 | ExpDemo 通道 |
| 5 | FSM 序列检测 | ✅ 操作说明+状态 | ExpDemo 通道 |
| 6 | VGA 彩条 | ⬜ 等 VGA 线 | 画廊频道 |
| 7 | VGA 图像 | ⬜ 等 VGA 线 | 画廊频道 |
| 8 | PS/2 键盘 | ✅ 驱动就绪 + 实板已验证 + LCD 回显 | `ps2_controller.vhd` + `lcd_debug.vhd` |
| 9 | UART 串行 | ⬜ 等 RS-232 线 | 已有 NEORV32 UART0 |
| 10 | 红外 NEC | ✅ 解码+频道切换 | `ir_nec_decoder.vhd` |
| 11 | DDS 频率合成 | ❌ 未验收 | 推迟 |
| 12 | 简单 CPU | ✅ 操作说明+状态 | ExpDemo 通道 |
| 13a | LCD (VHDL) | ✅ HD44780 驱动 + PS/2 键盘回显 | `lcd_debug.vhd` (SW16=1 实时回显) |

**12/13 已覆盖**。Exp6/7/9 等硬件就位后补上。

---

## 架构

```
┌─────────────────────────────────────────┐
│  VGA 文字终端 (vga_text_terminal.vhd)    │  ← 纯硬件, 被动显示
│  80×25, 双页, CP437 字库, RGB332 前景色   │
└──────────────┬──────────────────────────┘
               │ XBUS (0xF0000000)
┌──────────────▼──────────────────────────┐
│  de2shell (C, CPU 上运行)                │  ← 统一入口
│  - 命令解析 (shell_input)                 │
│  - 程序调度 (active_prog)                 │
│  - IR 映射 (handle_ir)                    │
│  - VGA HAL (vga_hal.c)                   │
│  - Board Status (board_status.c)         │
├─────────────────────────────────────────┤
│  子程序:                                     │
│  crypto │ snake │ life │ dashboard │ ps2     │
│  monitor │ info │ expdemo (11 实验多路复用)  │
└──────────────────────────────────────────┘
```

---

## 文件结构

```
sw/app/de2shell/
├── main.c          ← Shell 主循环 + 程序注册 + 调度
├── board_status.h/c← LCD/HEX/LED 统一状态层 + uptime
├── vga_hal.h/c     ← VGA 硬件抽象层 (ANSI / XBUS 0xF0000000)
├── gpio_hal.h/c    ← GPIO 硬件抽象层 (仿真 / NEORV32)
├── crypto.c        ← 密码学终端 (链接 crypto_cli/)
├── snake.c         ← 贪吃蛇
├── life.c          ← 康威生命游戏
├── dashboard.c     ← 系统仪表盘
├── monitor.c       ← 系统监控 (GPIO/UART 轮询)
├── ps2.c           ← PS/2 键盘扫描码测试
├── info.c          ← 系统信息页
├── hello.c         ← Phase 0 LED 跑马灯演示
├── memtest.c       ← Phase 1 SDRAM 4 项自检
└── makefile

src/rtl/periph/  (Phase 2b + Phase 3 VHDL)
├── vga_text_terminal.vhd
├── font_rom_pkg.vhd
├── ps2_controller.vhd   ← 16-entry FIFO + IRQ + scancode 直出
├── ps2_sync.vhd / ps2_receiver.vhd
├── lcd_debug.vhd         ← SW16=1: VGA/PS2 状态 + 键盘 ASCII 回显
├── lcd_wb.vhd            ← LCD Wishbone 控制器
├── ir_nec_wb.vhd         ← NEC IR 解码器 (Wishbone 接口)
├── ir_exp10.vhd          ← IR 实验10 适配器
├── ir_dbg_exp10.vhd      ← IR 实验10 调试适配器
├── expdemo_top.vhd       ← 硬件实验多路复用顶层
├── expdemo_wb.vhd        ← ExpDemo Wishbone 接口
├── intc_wb.vhd           ← 中断控制器
├── timer_wb.vhd          ← 定时器
├── ntt_sdf.vhd           ← NTT 加速器 (单文件, 编译通过)
├── led_patterns.vhd
├── digital_clock_core.vhd
└── sys_dashboard.vhd

src/rtl/periph/ (CDC + 互连)
├── async_fifo.vhd        ← 8-deep × 32-bit 双时钟域异步 FIFO
└── sdram_ctrl.vhd        ← SDRAM 控制器 (含 burst 支持)
```

## 待完成

- ~~VGA + PS/2 + IR 接入 `de2_115_top.vhd` / `wb_intercon` / QSF 引脚分配~~ ✅ (commit `07615ba`)
- ~~PS/2 上板验证~~ ✅ (扫描码、扩展键、Lock 灯同步均通过)
- ~~独立游戏合并入 de2shell~~ ✅ (snake.c / life.c 已合并)
- ~~memtest 展示收敛~~ ✅ (5 项自检 + ALL PASS 汇总)
- ~~life 手动模式~~ ✅ (WASD/方向键移动光标, 空格置生灭, 图案预设 G/N/R/C, 速度 +/-/P 暂停)
- ~~NTT C 驱动~~ ✅ (`ntt.c`/`ntt.h`, SW reference + HW MMIO, round-trip 验证 PASS)
- ⏳ dashboard/board_status 上板确认: 验证 `CHx TAG LIVE` 与 HEX/LED 映射
- ⏳ **VGA→HDMI 有源转换器到货** (预计 5/26 周一) → 上板验证 VGA 终端渲染
- ⏳ Exp6/7 画廊频道 (等 VGA 线后)
- ⏳ RS-232 线到后: Exp9 UART 验证
- ⏳ IR 遥控器频道切换 end-to-end (模块已就位，等 VGA 画面反馈)
- ⬜ NTT 接入 de2shell `ntt` 命令 (驱动就绪，待接入)
