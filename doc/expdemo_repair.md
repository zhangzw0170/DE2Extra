# ExpDemo 修复清单

## 收口目标

修复完成后的 `expdemo` 应满足以下口径：

1. 成为课程实验的唯一正式入口
2. 原实验的板级 I/O 行为保持可见、可验收
3. VGA / UART 只做 monitor，不篡改实验本体的展示语义
4. `de2shell` / `de2os` 只负责进入 `expdemo`、调试和系统级功能，不再维护平行实验入口
5. 实验本体保持纯 VHDL；允许复用 shell 侧已验证的外设封装、同步器、mux 和 monitor，但不允许用软件逻辑替代实验本体

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

**修复**：在 `expdemo_top` 层加 PS/2 扫描码监视器。当 channel=8 时，监视 PS/2 扫描码流，检测到 Del（make 0x71）后硬件自动将 channel 复位为 0。监视器需复用 `exp8_ps2_sync` + `exp8_ps2_receiver` 的逻辑，或 tap Exp8 输出的 scan_code/valid 信号。

### R2: Exp10 MENU 检测缺失

`irda_top` 只显示接收到的 NEC 命令码，不解析按键含义。当前没有硬件能检测 MENU 并触发退出。

**修复**：在 `expdemo_top` 层加 IR NEC 命令监视器。当 channel=10 时，监视 IR 接收的 NEC 命令码，检测到 MENU 按键码后硬件自动将 channel 复位为 0。需要确认 MENU 对应的 NEC 编码（查 IR 遥控协议表）。

### R3: Exp9 UART TXD 未接入

`de2_115_top.vhd` 中 `exp_uart_txd` 被赋值但从未接到顶层 `UART_TXD` 输出。当前 `UART_TXD` 直接接 CPU 的 `uart_txd_int`，Exp9 发出的数据到不了 RS-232 物理接口。

**同时**：`exp_uart_rxd` 直接接 `UART_RXD`，CPU 的 `UART_RXD` 也接同一个引脚。两者同时监听同一根线，不是 mux 关系，不会冲突但也不对——CPU 和 Exp9 都会收到同一帧数据。

**修复方案**（二选一）：
- (a) Exp9 不 mux UART：去掉 `exp_uart_txd` 输出，Exp9 用内部 loopback 演示，HEX/LEDR 显示收发数据。UART 始终留给 shell。文档中 "串口强制退出" 保持可行。
- (b) Exp9 激活时 mux UART：`UART_TXD` 按 channel 在 CPU 和 Exp9 之间切换。此时串口不可用，退出只能靠 PS2/IR/KEY。shell 的串口输出改走 JTAG UART。

## 重要问题

### R4: 输入侧 mux 未实现

当前 `de2_115_top.vhd` 中：
- `PS2_CLK/PS2_DAT` 直接接到 shell 的 `ps2_controller` 和 expdemo 的 `expdemo_top`，是**并联**关系，不是 mux
- `IRDA_RXD` 同理，并联接到 `ir_nec_wb` 和 `expdemo_top`
- 结果：CPU 的 PS2/IR 外设和 Exp8/10 同时收到相同的输入信号，会互相干扰（例如 Exp8 显示扫描码的同时，CPU shell 也在处理按键）

**修复**：在 `de2_115_top.vhd` 加输入侧 mux：
```
ps2_to_shell <= PS2_CLK when channel /= 8 else '0';
ps2_to_exp8  <= PS2_CLK when channel = 8 else '0';
```
IR 同理。

### R5: 导航盲区

进入 Exp8 后 PS/2 被占用，进入 Exp10 后 IR 被占用。CPU 固件无法通过这些外设接收用户导航输入。

**修复**：
- 退出（R1/R2）必须由硬件自动完成（写 channel=0）
- CPU 固件通过轮询 `STATUS` 寄存器检测 channel 回零，退出 expdemo 循环
- 非 Exp8/Exp10 的实验不受影响，PS2/IR 始终可用于导航

### R6: LCD 切换后可能需要重新初始化

`LCD_DATA/RS/RW/EN` 已在输出侧 mux（`de2_115_top.vhd:744-747`），切换到 Exp12/13a 时 LCD 输出来源会变。但 HD44780 初始化由驱动模块在复位后完成。如果从 shell 模式切到 Exp12/13a，LCD 可能处于 shell 的状态，需要 Exp12/13a 重新执行初始化序列。

**修复**：确认 Exp12/13a 的 LCD 驱动是否有持续初始化逻辑，或在 mux 切换时生成一个复位脉冲给对应适配器。

### R10: 保留通道 6/7 意外激活输出 mux

写入 channel=6 或 7（VGA 保留）时，`active_o` 仍然为 1，输出 mux 切到 expdemo 侧，但 case 落入 `when others`，板上 HEX/LEDR/LEDG 全部熄灭。此时 shell 输出也被切断，用户看到板子"死"了。

**修复**：`expdemo_wb.vhd` 中屏蔽写入 6/7，或将 `active_o` 逻辑改为 `channel /= 0 and channel /= 6 and channel /= 7`。

### R11: Exp10 的 `irda_top` 未单独验证

IR 端到端已通过（`ir_nec_wb`），但 Exp10 使用的是 `irda_top`（原始实验代码），与 shell 的 `ir_nec_wb` 是不同模块。`irda_top` 未在 DE2Extra 平台上单独验证。

**修复**：烧录后选择 Exp10（channel=10），用遥控器测试，确认 HEX 能显示接收到的 NEC 命令码。

## 次要问题

### R7: 所有实验始终运行

当前 11 个实验模块全部同时实例化且始终运行，仅输出被 mux 选择。切换 channel 时实验内部状态（计数器、FSM、移位寄存器）不会复位。切回某实验时会看到之前的状态。

**影响**：功能上不是 bug，但用户可能期望 "切换到实验 X 时从头开始"。

**可选修复**：在 `expdemo_top` 中对每个适配器加 per-channel 使能/复位门控，channel 变化时复位非活跃实验。

### R8: KEY0 共享复位

多个实验（Exp9、Exp10 等）使用 KEY0 作为复位。在 expdemo 模式下按下 KEY0 会同时复位所有实验和 CPU，无法单独复位当前实验。

**影响**：低。expdemo 模式下 CPU 不应被复位（否则 channel 寄存器归零、退出 expdemo）。

**可选修复**：expdemo 模式下屏蔽 KEY0 对 CPU 的影响，或在适配器层做 KEY0 与 channel 的门控。

### R9: Exp2/3 自生时钟的 Timing Warning

Exp2（led_display）和 Exp3（hex_scan）内部用逻辑分频生成 `clk1_div`/`clk2_div`/`clk_1hz`，Quartus 报 "determined to be a clock but was found without an associated clock assignment" 警告。

**影响**：编译通过，时序满足。仅产生大量 warnings。

**可选修复**：将分频时钟改为使能时钟（clock enable）风格，消除 warnings。
