# v1→v2 路线对比与差距分析

> 日期: 2026-05-23
> 基于 v1 (FreeRTOS+LVGL, `archive/implementation_plan-v1-sof-rtos-gui.md`) 与 v2 (VGA 字符终端, `implementation_plan.md`) 的交叉对比。

---

## 路线变更概览

```
v1: M1→M2→M3→M4→M5→M6   (FreeRTOS+LVGL, 像素帧缓冲, A7Pro移植)
v2: Ph1→Ph2a/2b→Ph3       (bare-metal, 字符终端, DE2-115 only)
```

核心决策: 放弃 FreeRTOS+LVGL，改为纯硬件 VGA 字符终端 + bare-metal C shell。动机: 50MHz NEORV32 跑 LVGL 性能风险大，字符终端对教学演示更直观。

### 路线变更时间线

| 日期 | 版本 | 关键决策 |
|---|---|---|
| 2026-05-22 上午 | v1 | FreeRTOS+LVGL 路线制定 |
| 2026-05-22 下午 | v2 | 放弃 GUI 框架，改为纯硬件文字终端 |
| 2026-05-23 | v2 实施 | Phase 2a/2b/3 完成，v1 归档 |

---

## 里程碑对照

| v1 里程碑 | v1 目标 | v2 对应 Phase | 状态 | 评价 |
|---|---|---|---|---|
| M1 | SDRAM + wb_intercon | Phase 1 | ✅ 2026-05-23 调通 | 目标一致，按时完成 |
| M2 | 密码学 UART CLI | Phase 2a | ✅ 同日完成 | 目标一致 |
| M3 | VGA + PS/2 键盘 | Phase 2b | ✅ 源码齐，待上板 | 目标一致，实现方式不同 |
| M3 | **帧缓冲模式** | — | 🔄 改为字符缓冲 | 正确决策: 省 SDRAM，省 CPU |
| M3 | **PS/2 鼠标** | — | ❌ 删除 | 键盘够用，鼠标可选 |
| M3 | **PLL 25.175MHz** | — | 🔄 改为 DFF 25MHz | DFF 简单但 PLL 更标准 |
| M4 | **FreeRTOS 移植** | — | ❌ 删除 | 正确决策: 太重 |
| M4 | **LVGL 集成** | — | ❌ 删除 | 正确决策: 字符终端替代 |
| M4 | **系统定时器** | — | ❌ 删除 | busy-wait 替代，可后续补 |
| M4 | **中断控制器** | — | ❌ 删除 | PS/2 IRQ 直连 CPU |
| M5 | 密码学可视化 | Phase 3 | 🔄 Shell 命令替代 | 更轻量，超额完成 |
| M5 | 实验模块整合 | Phase 3 | ✅ 12/13 全覆盖 | 超过 v1 规划 (v1 仅 4 个) |
| M6 | **A7Pro 移植** | — | ❌ 删除 | 6/15 前来不及 |

---

## 关键差异详解

### 1. 帧缓冲 → 字符缓冲 (M3/Phase 2b)

| 方面 | v1 (帧缓冲) | v2 (字符缓冲) |
|---|---|---|
| 存储位置 | SDRAM 600KB | M9K 8KB (2 页 × 4KB) |
| 每像素 | 16-bit RGB565 | N/A |
| 每字符 | 软件渲染 8×16 像素 | 硬件查字库 ROM，16-bit [颜色\|ASCII] |
| VGA 控制器 | 扫描 SDRAM 地址，输出像素 | 扫描 M9K 地址，查字库，输出像素 |
| CPU 参与 | 渲染每个字符到 SDRAM | 只写字符码到 buffer |
| 优点 | 任意像素自由绘制 | CPU 极轻，硬件自动渲染 |
| 缺点 | CPU 像素渲染慢，需 SDRAM | 只能显示字库字符，无自由像素 |

### 2. FreeRTOS+LVGL → bare-metal de2shell (M4/Phase 3)

| 方面 | v1 | v2 |
|---|---|---|
| 调度 | FreeRTOS 抢占式 | de2shell 协作式 (init→update→input→finish) |
| 界面 | LVGL 控件 | VGA 字符 + CP437 块状字符绘制 |
| 内存 | SDRAM 128MB 全部可用 | IMEM 32KB + DMEM 16KB |
| 多任务 | 真多任务 (timer tick 切换) | 伪多任务 (轮询切换) |
| 复杂度 | 高 (port.c, 上下文切换, 临界区) | 低 (4 个回调) |
| 适合场景 | 需要 widgets 的复杂 GUI | 终端命令行 + 简单游戏 |

### 3. 砍掉的内容评估

| v1 项目 | 砍掉原因 | 是否值得捡回 |
|---|---|---|
| PS/2 鼠标 | 键盘 + IR 遥控器已覆盖输入 | 🟡 低优先: Terasic CD 有参考，~200 行 VHDL |
| PLL VGA 时钟 | DFF 二分频够用 | 🟡 中优先: 25.175MHz 更标准，兼容性更好 |
| 系统定时器 | busy-wait 够用 | 🟡 中优先: 省 CPU，~100 行 VHDL |
| 中断控制器 | PS/2 IRQ 直连 CPU | 🟢 不需: 当前外设少，不需要仲裁 |
| A7Pro 移植 | 6/15 前时间不足 | 🟢 不需: DE2-115 资源已足够 |
| FreeRTOS | 太重 | 🟢 正确砍掉 |
| LVGL | 50MHz 跑不动 | 🟢 正确砍掉 |

---

## v2 超额完成部分

| 项目 | v1 规划 | v2 实际 |
|---|---|---|
| CLI 框架 | 无 (依赖 LVGL) | Unified Shell + VGA HAL + GPIO HAL |
| 游戏 | 无 | 贪吃蛇 + Conway 生命游戏 (并入 de2shell) |
| 仪表盘 | 无 | sys_dashboard.vhd 渲染引擎 |
| 实验覆盖 | 4 个 (LCD/DDS/IR/PS2) | 12/13 已验收实验 (CLI 命令 + board 操作) |
| 红外遥控 | "验收后整合" | 已整合 NEC 解码器，shell 已预留 IR 映射 |
| VGA 双页 | 单帧缓冲 | 双页缓冲 (F1/F2)，硬件零延迟切换 |
| 文档 | 实施计划 | +验收表、实现记录、CD-ROM 参考手册 |
| 测试 | 仅上板 | +QuestaSim testbench、DPI-C 自动化测试 |

---

## 当前状态总览 (2026-05-23)

```
Phase 0 ████████████████████ 100%  CPU @50MHz 上板
Phase 1 ████████████████████ 100%  SDRAM + wb_intercon 调通
Phase 2a ████████████████████ 100%  Crypto CLI 验收
Phase 2b ██████████░░░░░░░░░░  60%  VGA/PS2 源码齐, 待上板联调
Phase 3  ██████████░░░░░░░░░░  50%  Shell + 实验就位, 待 VGA 线
```

| 当前卡点 | 影响 |
|---|---|
| VGA 转接线没到 | VGA 终端、仪表盘、游戏无法上板验证 |
| wb_intercon 需加 VGA/PS2 slave | 外设寄存器无法被 CPU 访问 |

---

## 待办清单 (6/15 前)

### 本周 (5/24-6/01): Phase 2b+3 联调

- [ ] wb_intercon 添加 VGA 和 PS/2 slave 端口
- [ ] QSF 添加 Phase 2b VHDL 文件 + VGA/PS2 引脚
- [ ] `sw/build.sh app/de2shell` 烧录验证
- [ ] VGA 转接线到 → 屏幕验证
- [ ] PS/2 键盘插入 → 终端输入验证
- [ ] IR 遥控器 → 频道切换验证

### 下周 (6/02-6/08): 功能完善

- [ ] Crypto CLI 并入 de2shell (替换桩)
- [ ] exp1.c 实时 GPIO 读取完善 (当前为桩)
- [ ] 系统定时器 (可选)
- [ ] 状态栏时间显示 (digital_clock_core 读数)
- [ ] PS/2 scancode → ASCII 转换 (软件层)

### 收尾 (6/09-6/15): 演示准备

- [ ] 演示脚本: 串口终端 → 密码学 → VGA 仪表盘 → 游戏 → IR 切换
- [ ] 所有验收表最终更新
- [ ] 资源占用报告
- [ ] 可选: 音频 Phase 4 (如果时间允许)

---

## v1 中可回收项目优先级

| 优先级 | 项目 | 时机 |
|---|---|---|
| **现在做** | PLL 25.175MHz VGA 时钟 | Phase 2b 上板前改 clk_rst_gen |
| **VGA 通后** | 系统定时器 (100 行 VHDL) | 优化 de2shell 延时 |
| **6/15 后** | PS/2 鼠标支持 | 参考 Terasic ps2.v |
| **6/15 后** | 音频 (Phase 4) | 参考 I2C_Controller + AUDIO_DAC |
| **永不** | FreeRTOS + LVGL | 字符终端已完全替代 |
