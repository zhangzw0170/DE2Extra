# expdemo KEY 映射表

## 约束

- 物理 `KEY0` 固定保留为 **整板硬复位**
- `expdemo` 中所有实验都不得再依赖物理 `KEY0`
- 一般规则：原实验里的 `KEY0/KEY1/KEY2` 顺延到物理 `KEY1/KEY2/KEY3`
- 特例：`Exp3` 的 `digital_clock` 子模式删除“写秒”，并把程序内复位放到 `KEY1`

## 引脚顺序复核

已对照当前 Quartus 引脚约束 [par/de2extra.qsf](par/de2extra.qsf)、仓库内备份 [DE2-115_pin_table_backup.md](DE2-115_pin_table_backup.md) 与板卡资源汇总 [DE2-115_Resource_Summary.md](doc/DE2-115_Resource_Summary.md) 中的 KEY 表，当前物理顺序为：

> 备注：原始 Excel 仍在仓库外 `E:\Main\JuniorII\NonExam\FPGA\DE2-115引脚表.xlsx`，仓库内现在保留了便于查阅的清洗备份。

| 物理键 | 引脚 |
| --- | --- |
| `KEY0` | `PIN_M23` |
| `KEY1` | `PIN_M21` |
| `KEY2` | `PIN_N21` |
| `KEY3` | `PIN_R24` |

## 最终映射表

| 通道 | 实验 | KEY3 | KEY2 | KEY1 | KEY0 | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Exp1 `3-8 Decoder` | 未使用 | 未使用 | 未使用 | 板级复位 | 纯组合逻辑 |
| 2 | Exp2 `LED Patterns` | 未使用 | 未使用 | 切换彩灯模式 | 板级复位 | 原 `KEY0 -> KEY1` |
| 3 | Exp3 `7-Segment Scan` | `digital_clock` 子模式下写时 | `digital_clock` 子模式下写分 | `digital_clock` 子模式下复位 | 板级复位 | 删除原 `KEY0` 写秒功能 |
| 4 | Exp4 `Dual-Port RAM` | 未使用 | 未使用 | 写模式下一次写入脉冲 | 板级复位 | 原 `KEY0 -> KEY1` |
| 5 | Exp5 `FSM Detector` | 未使用 | 未使用 | FSM 复位 | 板级复位 | 原 `KEY0 -> KEY1` |
| 8 | Exp8 `PS/2 Scan Codes` | 未使用 | 未使用 | 未使用 | 板级复位 | 退出靠键盘 `Del` |
| 9 | Exp9 `UART` | 未使用 | 未使用 | 发送当前 `SW[7:0]` | 板级复位 | 原 `KEY0 -> KEY1` |
| 10 | Exp10 `IR NEC` | 未使用 | 未使用 | 清空/复位红外显示状态 | 板级复位 | 原 `KEY0 -> KEY1` |
| 11 | Exp11 `DDS` | 未使用 | 未使用 | DDS 复位 | 板级复位 | 原 `KEY0 -> KEY1` |
| 12 | Exp12 `Simple CPU` | 自动/手动模式切换 | 单步执行一个状态 | 主复位 | 板级复位 | 原 `KEY0/1/2 -> KEY1/2/3` |
| 13 | Exp13 `LCD SoC` | 未使用 | 未使用 | 循环切换 LCD 消息页 | 板级复位 | 原 `KEY0 -> KEY1` |

## 实验说明速查

### Exp1

- `SW2:0`：输入 `A/B/C`
- `SW5`：`G1`
- `SW4`：`G2A`
- `SW3`：`G2B`
- `KEY`：无实验内功能，`KEY0` 仍为板级复位
- `LEDR7:0`：译码输出

### Exp2

- `SW0`：总使能
- `KEY1`：切换彩灯模式
- `LEDR[17:0]`：显示 18 位重写彩灯图样
- `HEX2='E'`、`HEX1='2'`、`HEX0=模式号`

### Exp3

`Exp3` 是四子模式实验：

- `SW17:16 = 00`：`seg_decoder`
- `SW17:16 = 01`：`hello_display`
- `SW17:16 = 10`：`hex_scan`
- `SW17:16 = 11`：`digital_clock`

只有 `digital_clock` 子模式使用按键：

- `KEY1`：复位
- `KEY2`：写分
- `KEY3`：写时
- 原 `KEY0` 写秒功能已删除

### Exp4

- `SW17`：`1=写`，`0=读`
- `SW15:11`：地址
- `SW7:0`：数据
- `KEY1`：写模式下一次写入脉冲

### Exp5

- `SW0`：输入 `w`
- `SW17:16`：选择不同 FSM
- `KEY1`：复位

### Exp8

- 主输入设备：PS/2 键盘
- `Del`：返回 `expdemo` 主页

### Exp9

- `SW7:0`：待发送字节
- `KEY1`：触发发送

### Exp10

- `SW0`：调试显示模式
- `KEY1`：清空当前译码显示
- 遥控器 `MENU`：返回 `expdemo` 主页

### Exp11

- `SW7:0`：`fword`
- `SW8`：模式切换
- `KEY1`：复位 DDS

### Exp12

- `KEY1`：复位
- `KEY2`：单步执行
- `KEY3`：自动/手动切换
- `SW16`：LCD 详细模式

### Exp13

- `SW7:0`：LCD 数据/页面输入
- `KEY1`：切换消息页
- `LCD`：主显示设备
