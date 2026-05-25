# ExpDemo 修复清单

## 收口目标

修复完成后的 `expdemo` 应满足以下口径：

1. 成为课程实验的唯一正式入口
2. 原实验的板级 I/O 行为保持可见、可验收
3. VGA / UART 只做 monitor，不篡改实验本体的展示语义
4. `de2shell` / `de2os` 只负责进入 `expdemo`、调试和系统级功能，不再维护平行实验入口
5. 实验本体保持纯 VHDL；允许复用 shell 侧已验证的外设封装、同步器、mux 和 monitor，但不允许用软件逻辑替代实验本体

## 当前状态（2026-05-24）

已完成：

1. `expdemo` 已成为 shell 中唯一正式实验入口，原 `exp1/4/5/12` 平行命令已删除
2. `expdemo` Wishbone MMIO 已写通；`0xF000D000` 可读回，串口实测 `1 + Enter -> HW channel: 1`
3. `expdemo` 软件页已改为“Home -> 实验说明 + Live Monitor”两级界面；进入实验后显示该实验的 SW/KEY/I/O 说明与实时输入监视
4. `KEY0` 已从 `expdemo` 实验输入中释放，当前实现改为物理 `KEY0` 固定保留板级复位；各实验 `KEY` 重映射见 `expdemo-key-map.md`
5. `Exp3 / digital_clock` 已按口径删除“写秒”，程序内复位优先放到 `KEY1`
6. `R1/R2/R5` 已在 RTL 收口并在本轮上板验证通过：Exp8 检测 `Del` 自动回主页 ✅，Exp10 检测 `MENU` 自动回主页 ✅，CPU 侧检测 `channel=0` 后回到 Home ✅
7. `R3/R4/R10` 已在 RTL 收口：Exp9 UART TXD 已接入顶层 mux，PS/2/IR 输入已按 channel 做输入侧 mux，保留通道 `6/7` 已屏蔽
8. shell 全局 `KEY1/KEY2/KEY3` 热键在 `expdemo` 内已禁用，避免与实验按键冲突

当前尚未完成的一点是：以上 `KEY` 重映射与新版 `Home/说明/monitor` 页面已在本轮上板全量回归通过。H 系列串口验收项全部 ✅。

当前仍需优先处理的剩余项：

1. `R7`：是否需要做”切换实验即局部复位”的 per-channel reset，属于体验优化
2. `R9`：Exp2/3 自生时钟的 timing warning 仍在，当前不阻塞功能

## 实现边界

- 应优先复用已存在的纯 VHDL 模块和外围适配逻辑，避免把原实验“整份复制”到 `expdemo`
- 新增代码应集中在：
  - `expdemo_top` 的通道/退出/外设仲裁
  - `de2_115_top` 的输入输出 mux
  - 原实验到统一 `exp_out_t` 接口的轻量适配层
- 不应新增：
  - 仅为 `expdemo` 存在、但与原实验逻辑重复的大块功能副本
  - 由 C 程序生成实验效果、再冒充“实验通过”的替代实现

## 关键问题

### R1: Exp8 Del 检测缺失

`exp8_ps2_keyboard` 是被动扫描码显示器，只把收到的字节亮在 HEX 上，不解析任何按键。当前没有硬件能检测 Del（0x71）并触发退出。

**当前实现**：已在 `expdemo_top` 中加入独立 PS/2 监视器，检测到 Del make code 后拉起 `force_shell_i`，由 `expdemo_wb` 把 channel 置回 0。

### R2: Exp10 MENU 检测缺失

`irda_top` 只显示接收到的 NEC 命令码，不解析按键含义。当前没有硬件能检测 MENU 并触发退出。

**当前实现**：已在 `expdemo_top` 中加入 `ir_dbg_exp10` 监视器；当 channel=10 且命令码为 `0x11` (`MENU`) 时，硬件自动把 channel 拉回 0。

### R3: Exp9 UART TXD 未接入

`de2_115_top.vhd` 中 `exp_uart_txd` 被赋值但从未接到顶层 `UART_TXD` 输出。当前 `UART_TXD` 直接接 CPU 的 `uart_txd_int`，Exp9 发出的数据到不了 RS-232 物理接口。

**同时**：`exp_uart_rxd` 直接接 `UART_RXD`，CPU 的 `UART_RXD` 也接同一个引脚。两者同时监听同一根线，不是 mux 关系，不会冲突但也不对——CPU 和 Exp9 都会收到同一帧数据。

**当前实现**：采用方案 (b)。`UART_TXD` 在 channel=9 时切到 Exp9，其余时候仍由 CPU 驱动；CPU 日志额外桥接到 JTAG UART，避免 Exp9 活跃时 shell 串口链路完全失明。

## 重要问题

### R4: 输入侧 mux 未实现

**已决定不修复**：Exp8/Exp10 改用 shell 内置 `ps2` 和 `monitor`/`dash` 程序代替，不再需要硬件输入侧 mux。

### R5: 导航盲区

**已决定不修复**：同 R4，Exp8/10 不再需要硬件退出检测。

### R6: LCD 切换后可能需要重新初始化

`LCD_DATA/RS/RW/EN` 已在输出侧 mux（`de2_115_top.vhd:744-747`），切换到 Exp12/13a 时 LCD 输出来源会变。但 HD44780 初始化由驱动模块在复位后完成。如果从 shell 模式切到 Exp12/13a，LCD 可能处于 shell 的状态，需要 Exp12/13a 重新执行初始化序列。

**已确认**：上板实测 shell/Exp12/Exp13a 之间切换后 LCD 均能正常重初始化，无需额外复位脉冲。

### R10: 保留通道 6/7 意外激活输出 mux

写入 channel=6 或 7（VGA 保留）时，`active_o` 仍然为 1，输出 mux 切到 expdemo 侧，但 case 落入 `when others`，板上 HEX/LEDR/LEDG 全部熄灭。此时 shell 输出也被切断，用户看到板子"死"了。

**当前实现**：`expdemo_wb.vhd` 已同时做了两层保护：
- 写 channel 寄存器时直接屏蔽 `6/7`
- `active_o` 只在 `channel /= 0 and channel /= 6 and channel /= 7` 时拉高

### R11: Exp10 的 `irda_top` 未单独验证

**已决定不验证**：Exp10 改用 shell 内置 IR 功能代替，`irda_top` 不再需要单独上板确认。

## 次要问题

### R7: 所有实验始终运行

当前 11 个实验模块全部同时实例化且始终运行，仅输出被 mux 选择。切换 channel 时实验内部状态（计数器、FSM、移位寄存器）不会复位。切回某实验时会看到之前的状态。

**影响**：功能上不是 bug，但用户可能期望 "切换到实验 X 时从头开始"。

**可选修复**：在 `expdemo_top` 中对每个适配器加 per-channel 使能/复位门控，channel 变化时复位非活跃实验。

### R8: KEY0 共享复位

旧问题：多个实验（Exp9、Exp10 等）使用 KEY0 作为复位。在 expdemo 模式下按下 KEY0 会同时复位所有实验和 CPU，无法单独复位当前实验。

**当前处理**：已在适配层统一释放物理 `KEY0`，保留为整板硬复位；默认把原实验 `KEY0/1/2` 顺延到物理 `KEY1/2/3`，`Exp3` 再单独删除”写秒”并把复位放到 `KEY1`。

**已确认**：上板逐实验复测通过，`KEY1/2/3` 按新映射正常工作。

### R9: Exp2/3 自生时钟的 Timing Warning

Exp2（led_display）和 Exp3（hex_scan）内部用逻辑分频生成 `clk1_div`/`clk2_div`/`clk_1hz`，Quartus 报 "determined to be a clock but was found without an associated clock assignment" 警告。

**影响**：编译通过，时序满足。仅产生大量 warnings。

**可选修复**：将分频时钟改为使能时钟（clock enable）风格，消除 warnings。
