# ExpDemo — 硬件实验演示系统

将 13 个课程实验以真实 VHDL 硬件形式集成到 DE2Extra 中，通过 VGA 导航界面选择实验，板载外设即时展示效果。

## 设计原则

1. `expdemo` 是课程实验的唯一正式入口。
   `de2shell` / `de2os` 不再长期保留 `exp1`、`exp4`、`exp5`、`exp12` 这类平行命令作为面向用户的主路径。
2. 面向用户的实验输入输出，必须尽量保持原实验口径。
   除 `KEY0` 保留板级 reset 语义外，SW / KEY / HEX / LED / LCD 的主显示行为应与原实验一致。
3. VGA 与串口只承担 monitor / 远程诊断角色。
   它们用于显示实验状态、调试信息和退出提示，但不替代原实验在板级外设上的展示。
4. 实验本体必须保持纯 VHDL 实现。
   `expdemo` 可以复用 `de2shell` 里已经验证过的总线封装、输入同步、显示适配、monitor 和 mux 逻辑，但被展示的实验逻辑本身不能退化成 C 侧模拟。
5. 优先复用，避免平移复制。
   只有当原实验模块无法直接接入 `expdemo` 时，才允许写适配层；适配层的职责应限于接口转换、信号整理和板级输出归一化。

## 入口

从 shell 通过以下任一方式进入 expdemo：

- 串口/VGA 终端：输入 `demo` 命令
- IR 遥控：按下指定按键

进入后，VGA 显示实验选择菜单，PS/2 键盘和 IR 遥控用于导航。

## 导航

- PS/2 键盘：数字键选择实验编号，确认激活
- IR 遥控：数字键选择实验编号，确认激活
- HEX0-1 显示当前选中编号，HEX2-7 显示实验名称缩写

## 外设独占规则

多数实验只使用 HEX/LEDR/LEDG（输出），导航设备（键盘 + IR）不受影响。

板级展示优先级如下：

1. 原实验规定的板级外设行为
2. `expdemo` 的导航 / 通道切换
3. VGA / UART monitor 的旁路观测

以下实验需要独占输入外设：

| 实验 | 独占外设 | 退出条件 |
|------|---------|---------|
| Exp8 (PS/2 键盘扫描码) | PS/2 键盘 | 按下 Del |
| Exp10 (IR 红外解码) | IR 遥控 | 按下 MENU |

独占期间，该外设交给实验模块使用，导航侧无法使用。

## 退出

- 独占实验：按下退出键（Del / MENU）后，交还外设控制权，自动退出 expdemo 回到 shell
- 非独占实验：导航设备随时可切换到其他实验或按 Esc 返回 shell
- 串口：任意时刻输入命令可强制退出

## Monitor 约定

- VGA：显示当前实验编号、实验名称、关键状态字、输入输出解释、退出提示
- UART：输出与 VGA 一致或更详细的文本调试信息，便于远程验收
- monitor 的存在不应改变实验本体的硬件输入输出协议

## Channel 映射

Channel = 实验编号，写入 WB 寄存器 `0xF000D000`：

| Channel | 实验 | HEX | LEDR | LEDG | LCD | 独占 |
|---------|------|-----|------|------|-----|------|
| 0 | Shell | seg7_mapper | GPIO | GPIO | lcd_status | — |
| 1 | Exp1 译码器 | — | 译码输出 | — | — | — |
| 2 | Exp2 彩灯 | 模式名 | — | 彩灯 | — | — |
| 3 | Exp3 数码管 | 时钟/扫描 | 回显 | — | — | — |
| 4 | Exp4 存储器 | 地址+数据 | SW镜像 | 读出数据 | — | — |
| 5 | Exp5 FSM | FSM编号 | w指示 | 检测+移位 | — | — |
| 6 | *(保留)* | | | | | |
| 7 | *(保留)* | | | | | |
| 8 | Exp8 PS/2 | 扫描码 | — | — | — | PS/2 |
| 9 | Exp9 UART | 收发数据 | 接收+发送 | — | — | — |
| 10 | Exp10 IR | 命令历史 | 命令码 | 心跳+调试 | — | IR |
| 11 | Exp11 DDS | — | — | 正弦幅度 | — | — |
| 12 | Exp12 CPU | IR/PC/AC | 模式+AC | 步数 | 反汇编 | — |
| 13 | Exp13a LCD SOC | 消息编号 | — | — | 双行文本 | — |

## 架构

```
de2_115_top.vhd
├── neorv32_wrapper (CPU — 仅用于导航/调试/monitor)
├── wb_intercon
│   └── s8: expdemo_wb  ← 0xF000D000
│
├── expdemo_top
│   ├── channel_reg     — 当前通道
│   ├── adapt_exp1 ~ adapt_exp13a  — 纯 VHDL 实验 + 必要适配层
│   ├── output_mux      — HEX/LEDR/LEDG/LCD 多路复用
│   └── peripheral_mux  — PS2/UART/IR 输入侧切换
│
└── output_router       — board outputs: shell or expdemo
```
