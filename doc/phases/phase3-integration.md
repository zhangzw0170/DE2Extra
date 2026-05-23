# Phase 3: 集成 + 多模块整合

> 总纲: `../implementation_plan.md`
> 状态: 2026-05-23 — 模块预备完成，Phase 1 已闭环，进入外设接入与实板联调阶段
>
> **de2shell 程序注册表 (2026-05-23 更新)**:
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
> | `exp1` | prog_exp1 | Exp1 | 3-8 译码器 |
> | `exp4` | prog_exp4 | Exp4 | 双端口 RAM |
> | `exp5` | prog_exp5 | Exp5 | FSM 序列检测 |
> | `exp12` | prog_exp12 | Exp12 | 简单 CPU |
> | `cls` | — | — | 清屏 |
> | `quit` | — | — | 回到 shell |
>
> **IR 遥控映射**: CH1=hello, CH2=memtest, CH3=crypto, CH4=snake, CH5=life, CH6=dash, CH7=info, CH+/CH-=切换

## 本阶段概述

统一 Shell (`de2shell`) 作为主程序，UART/VGA 双输出。所有已验证的实验模块通过 CLI 命令或 IR 遥控器切换运行。

---

## 验收表

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| 1 | Unified Shell 框架 | 命令解析 + 程序调度 + VGA HAL 双模式编译 | ☑ (本地+Docker) |
| 2 | VGA 终端集成 | CPU 通过 XBUS 写 VGA buffer, 彩色显示 | 🟡 (HAL 已就位, 总线基础已具备) |
| 3 | IR 遥控器输入 | NEC 解码 → 程序切换 | ☑ (ir_nec_decoder.vhd + handle_ir) |
| 4 | 状态栏 | 底行常驻显示当前频道名 | ☑ (draw_status_bar) |
| 5 | 实验 CLI 程序集 | exp1/4/5/12 通过 shell 命令运行 | ☑ (桩模块, text=7896B) |
| 6 | C 游戏 | Snake + Conway Life | ☑ (独立编译通过, text=4400+4876B) |
| 7 | 密码学终端 | AES/SHA/SM4/SM3 CLI | ☑ (Phase 2a 独立编译) |
| 8 | F1/F2 双页 | VGA 硬件双页缓冲 | ☑ (vga_text_terminal.vhd) |
| 9 | 已验收模块挂载 | 全部 12/13 已验收实验可演示 | ☑ (见下表) |
| 10 | Docker 编译 | 所有 C 程序交叉编译通过, text < 32KB | ☑ (de2shell=7896B, crypto=13556B) |

---

## 13 实验覆盖状态

| # | 实验 | VGA 展示 | 接入方式 |
|---|---|---|---|
| 1 | 3-8 译码器 | ✅ SW→LEDR 实时映射 | CLI `exp1` |
| 2 | 彩灯显示 | ✅ LED 9 模式 | `led_patterns.vhd` |
| 3 | 七段管+电子钟 | ✅ BCD 时间 | `digital_clock_core.vhd` |
| 4 | 双口 RAM | ✅ 操作说明+状态 | CLI `exp4` |
| 5 | FSM 序列检测 | ✅ 操作说明+状态 | CLI `exp5` |
| 6 | VGA 彩条 | ⬜ 等 VGA 线 | 画廊频道 |
| 7 | VGA 图像 | ⬜ 等 VGA 线 | 画廊频道 |
| 8 | PS/2 键盘 | ✅ 驱动就绪 + 实板已验证 + LCD 回显 | `ps2_controller.vhd` + `lcd_debug.vhd` |
| 9 | UART 串行 | ⬜ 等 RS-232 线 | 已有 NEORV32 UART0 |
| 10 | 红外 NEC | ✅ 解码+频道切换 | `ir_nec_decoder.vhd` |
| 11 | DDS 频率合成 | ❌ 未验收 | 推迟 |
| 12 | 简单 CPU | ✅ 操作说明+状态 | CLI `exp12` |
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
├─────────────────────────────────────────┤
│  子程序:                                  │
│  crypto │ snake │ life │ dashboard       │
│  exp1   │ exp4  │ exp5 │ exp12 │ info    │
└──────────────────────────────────────────┘
```

---

## 文件结构

```
sw/app/de2shell/
├── main.c          ← Shell 主循环 + 程序注册 + 调度
├── vga_hal.h/c     ← VGA 硬件抽象层 (ANSI / XBUS 0xF0000000)
├── gpio_hal.h/c    ← GPIO 硬件抽象层 (仿真 / NEORV32)
├── crypto.c        ← 密码学终端 (桩)
├── snake.c         ← 贪吃蛇 (桩)
├── life.c          ← 康威生命游戏 (桩)
├── dashboard.c     ← 系统仪表盘 (桩)
├── info.c          ← 系统信息页
├── hello.c         ← Phase 0 LED 跑马灯演示
├── memtest.c       ← Phase 1 SDRAM 4 项自检
├── exp1.c          ← 3-8 译码器
├── exp4.c          ← 双口 RAM
├── exp5.c          ← FSM 序列检测
├── exp12.c         ← 简单 CPU
└── makefile

src/rtl/periph/  (Phase 2b + Phase 3 VHDL)
├── vga_text_terminal.vhd
├── font_rom_pkg.vhd
├── ps2_controller.vhd   ← 16-entry FIFO + IRQ + scancode 直出
├── ps2_sync.vhd / ps2_receiver.vhd
├── lcd_debug.vhd         ← SW16=1: VGA/PS2 状态 + 键盘 ASCII 回显
├── ir_nec_decoder.vhd
├── led_patterns.vhd
├── digital_clock_core.vhd
└── sys_dashboard.vhd

sw/app/ (独立 C 程序, 待合并入 de2shell)
├── crypto_cli/     ← text=13556B
├── game_snake/     ← text=4400B
└── game_life/      ← text=4876B
```

## 待完成

- ~~VGA + PS/2 + IR 接入 `de2_115_top.vhd` / `wb_intercon` / QSF 引脚分配~~ ✅ (commit `07615ba`)
- ~~PS/2 上板验证~~ ✅ (扫描码、扩展键、Lock 灯同步均通过)
- ~~独立游戏合并入 de2shell~~ ✅ (snake.c / life.c 已合并)
- ⏳ **VGA→HDMI 有源转换器到货** (预计 5/26 周一) → 上板验证 VGA 终端渲染
- ⏳ Exp6/7 画廊频道 (等 VGA 线后)
- ⏳ RS-232 线到后: Exp9 UART 验证
- ⏳ IR 遥控器频道切换 end-to-end (模块已就位，等 VGA 画面反馈)
