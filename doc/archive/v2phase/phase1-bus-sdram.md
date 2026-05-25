# Phase 1: 总线 + SDRAM 可靠

> **计划执行时间: 2026-05-23 14:12** | **归档: Phase 1 全部验收通过**
> 总纲: `../implementation_plan.md`
> 状态: 2026-05-23 — 已完成，`sdram_test` = `ALL PASS`

## 本阶段概述

修复 SDRAM 控制器的 hold timing 违例，实现通用 Wishbone interconnect 替换硬编码地址解码。
这是所有后续 Phase 的硬件基础，当前已经形成稳定可复现实板结果。

完整调试过程见: `phase1-sdram-debug-report.md`

---

## 验收表

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| 1 | SDRAM Hold Timing 修复 | Quartus TimeQuest 报告 TNS >= 0 | ✅ |
| 2 | wb_intercon 地址解码 | 未映射地址返回 bus error，无死锁 | ✅ |
| 3 | SDRAM 通过 interconnect | `sdram_test` 通过 wb_intercon 仍然 ALL PASS | ✅ |
| 4 | Quartus 编译通过 | 无错误，无关键警告 | ✅ |

---

## 1.1 修复 SDRAM Hold Timing

**问题**: `clk_sdram` (100MHz) 域 hold timing 违例 (TNS = -0.804ns)。

**方案**: 50MHz 侧信号在进入 100MHz 域的同步器前先打一拍 (CDC 前置寄存器)。

## 1.2 Wishbone Interconnect (`wb_intercon.vhd`)

通用地址解码，新外设只需在地址表加一行。单 master (NEORV32 XBUS)，多 slave。

**地址空间**:

| 起始地址 | 大小 | 外设 | Phase |
|---|---|---|---|
| 0x01000000 | 128MB | SDRAM | 1 |
| 0xF0000000 | 8KB | VGA 终端 | 2b |
| 0xF0002000 | 4KB | PS/2 键盘 | 2b |
| 0xF0004000 | 4KB | 系统定时器 | 3 (可选) |
| 0xF0006000 | 4KB | 中断控制器 | 3 (可选) |
| 0xF0008000 | 4KB | LCD 控制器 (已实现) | - |
| 0xF0009000 | 4KB | IR 接收器 | 3 (验收后) |
| 0xF000A000 | 4KB | DDS 音频 | 3 (验收后) |
| 0xF000B000 | 4KB | SD 卡 (SPI) | 3 (可选) |

## 文件变更

| 操作 | 文件 |
|---|---|
| 新建 | `src/rtl/bus/wb_intercon.vhd` |
| 修改 | `src/rtl/de2_115_top.vhd` — 替换硬编码地址解码为 wb_intercon |
| 修改 | `src/rtl/lib/de2extra_pkg.vhd` — 添加完整地址常量 |
| 修改 | `src/rtl/periph/sdram_ctrl.vhd` — 修复 CDC 同步 |
| 修改 | `par/de2extra.qsf` — 添加新文件 |
| 修改 | `constraints/de2extra.sdc` — 添加 CDC 约束 |
