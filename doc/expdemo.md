# ExpDemo — 硬件实验演示系统

将 13 个课程实验以真实 VHDL 硬件形式集成到 DE2Extra 中，通过 `expdemo` 统一进入。串口 / VGA 页面只负责导航、说明和 monitor，实验本体仍由板载外设直接展示。

## 设计原则

1. `expdemo` 是课程实验的唯一正式入口。
   `de2shell` / `de2os` 不再长期保留 `exp1`、`exp4`、`exp5`、`exp12` 这类平行命令作为面向用户的主路径。
2. 面向用户的实验输入输出，必须尽量保持原实验口径。
   除 `KEY0` 固定保留板级 reset 语义外，SW / KEY / HEX / LED / LCD 的主显示行为应与原实验一致。
3. VGA 与串口只承担 monitor / 远程诊断角色。
   它们用于显示实验状态、调试信息和退出提示，但不替代原实验在板级外设上的展示。
4. 实验本体必须保持纯 VHDL 实现。
   `expdemo` 可以复用 `de2shell` 里已经验证过的总线封装、输入同步、显示适配、monitor 和 mux 逻辑，但被展示的实验逻辑本身不能退化成 C 侧模拟。
5. 优先复用，避免平移复制。
   只有当原实验模块无法直接接入 `expdemo` 时，才允许写适配层；适配层的职责应限于接口转换、信号整理和板级输出归一化。

## 入口

从 shell 通过以下任一方式进入 expdemo：

- 串口/VGA 终端：输入 `expdemo` 命令
- IR 遥控：按下指定按键

进入后，`expdemo` 分为两个页面：

1. **主页 / Home**
   展示所有可选实验、当前选中项、进入方式
2. **实验说明 + Live Monitor 页**
   上半部分展示该实验的操作说明
   下半部分展示实时监视信息（SW / KEY / IR / channel / status / uptime）

## 导航

- 串口 / VGA Home：
  - 数字键 + Enter：进入实验
  - `+/-`：浏览实验编号
  - `Backspace`：删除已输入编号
  - `q`：退出到 shell
- IR：
  - 数字键：输入实验编号
  - `CH+/CH-`：浏览实验
  - `RETURN/PLAY`：进入实验
  - Home 页下 `MENU`：退出到 shell
- 进入实验后：
  - 页面切到“实验说明 + Live Monitor”
  - `q` 或 `MENU`：返回 `expdemo` 主页
  - 输入另一个编号 + Enter：切换实验
  - shell 的全局 `KEY1/KEY2/KEY3` 快捷键在 `expdemo` 内禁用，避免吞掉实验本体按键

## 外设独占规则

多数实验只使用 HEX / LEDR / LEDG / LCD（输出），导航页面只在 Home 或说明页中提供辅助文字，不替代板载显示。

板级展示优先级如下：

1. 原实验规定的板级外设行为
2. `expdemo` 的导航 / 通道切换
3. VGA / UART monitor 的旁路观测

以下实验需要独占输入外设：

| 实验 | 独占外设 | 退出条件 |
|------|---------|---------|
| Exp8 (PS/2 键盘扫描码) | PS/2 键盘 | 按下 Del 返回 Home |
| Exp10 (IR 红外解码) | IR 遥控 | 按下 MENU 返回 Home |

独占期间，该外设交给实验模块使用，导航侧无法使用。

## 退出

- 独占实验：按下退出键（Del / MENU）后，交还外设控制权，自动回到 `expdemo` 主页
- 非独占实验：在说明页输入 `q` / `MENU` 回主页，主页再 `q` 退出 shell
- 串口：任意时刻可重新输入实验编号并按 Enter 切换

## Monitor 约定

- Home 页：显示所有实验列表与当前选择
- 实验页上半部分：显示该实验的操作说明（SW / KEY / I/O / exit）
- 实验页下半部分：显示实时 monitor（`SW[17:0]`、`KEY[3:1]`、IR、channel、status、uptime）
- UART：与 VGA 保持同一口径，便于远程验收
- monitor 的存在不应改变实验本体的硬件输入输出协议
- monitor 只显示 CPU 当前可观测到的输入和状态寄存器，不伪造板级 `HEX/LEDR/LEDG/LCD` 回读值

## KEY 规则

- `KEY0` 永远保留为整板硬复位
- `expdemo` 内不再把物理 `KEY0` 传给实验本体
- 默认重映射规则：
  - 原 `KEY0 -> KEY1`
  - 原 `KEY1 -> KEY2`
  - 原 `KEY2 -> KEY3`
- 特例：
  - `Exp3 / digital_clock` 删除“写秒”，改为：
    - `KEY1`：复位
    - `KEY2`：写分
    - `KEY3`：写时
  - `Exp5 / FSM Detector` 改为：
    - `KEY1`：复位
    - `KEY2`：手动步进采样

完整表见 [expdemo-key-map.md](doc/expdemo-key-map.md)。

## Channel 映射

Channel = 实验编号，写入 WB 寄存器 `0xF0010000`：

| Channel | 实验 | HEX | LEDR | LEDG | LCD | 独占 |
|---------|------|-----|------|------|-----|------|
| 0 | Shell | seg7_mapper | GPIO | GPIO | lcd_status | — |
| 1 | Exp1 译码器 | — | 译码输出[7:0] | — | — | — |
| 2 | Exp2 彩灯 | E2+模式名 | 彩灯[17:0] | — | — | — |
| 3 | Exp3 数码管 | 时钟/扫描 | 回显 | — | — | — |
| 4 | Exp4 存储器 | 地址+数据 | SW镜像 | 读出数据 | — | — |
| 5 | Exp5 FSM | FSM编号(HEX6) | w+输入位 | 检测+移位历史 | — | — |
| 6 | *(保留)* | | | | | |
| 7 | *(保留)* | | | | | |
| 8 | Exp8 PS/2 | 扫描码[7:0] | — | — | — | PS/2 |
| 9 | Exp9 UART | RX[5:4]+TX[1:0] | 接收[15:0] | 发送[7:0] | — | — |
| 10 | Exp10 IR | 命令3级+计数 | 命令码[7:0] | 心跳+调试 | — | IR |
| 11 | Exp11 DDS | — | 正弦幅度[9:0] | — | — | — |
| 12 | Exp12 CPU | IR/PC/AC | 模式+AC | 步数 | 反汇编 | — |
| 13 | Exp13a LCD SOC | 消息编号(HEX0) | — | — | 双行文本 | — |

## 架构

```
de2_115_top.vhd
├── neorv32_wrapper (CPU — 仅用于导航/调试/monitor)
├── wb_intercon
│   └── s8: expdemo_wb  ← 0xF0010000
│
├── expdemo_top
│   ├── channel_reg     — 当前通道
│   ├── adapt_exp1 ~ adapt_exp13a  — 纯 VHDL 实验 + 必要适配层
│   ├── output_mux      — HEX/LEDR/LEDG/LCD 多路复用
│   └── peripheral_mux  — PS2/UART/IR 输入侧切换
│
└── output_router       — board outputs: shell or expdemo
```
