# Phase 1: SDRAM 调试完整记录

> **计划执行时间: 2026-05-23 16:05** | **归档: 三层根因全部修复，memtest ALL PASS**
> 相关阶段文档: `phase1-bus-sdram.md`
> 最终结果: `sdram_test` 四项测试全部通过，LCD 显示 `ALL PASS`

## 1. 调试目标

让 DE2-115 上的外部 SDRAM 通过 NEORV32 XBUS 稳定读写，并且在 `sw/app/sdram_test` 中通过以下四项测试：

1. `TEST1` walking ones immediate
2. `TEST2` walking ones bulk
3. `TEST3` checkerboard
4. `TEST4` address-as-data

---

## 2. 最初现象

最开始上板后，LCD 显示过多种失败模式：

- `FAIL T1 W00 GOT 80003FDC`
- `FAIL T1 W13 GOT 5FFBBFFF`
- `FAIL T1 W31 GOT 7FFBBFFF`
- `FAIL T1 W00 GOT 80003EFC`

其中还出现过两类容易误判的现象：

1. `FAIL T0 W00 GOT 00000000` / `0000FFFF`
   - 这不是新的硬件问题。
   - 当时板上没烧新程序，或者运行的是一版临时改坏了 LCD 协议的测试程序。
2. 某些 `GOT` 值大量高位为 `1`
   - 这看起来像“某几根 DQ 线坏了”，但后面证明不是固定引脚损坏，而是读路径本身不稳定。

---

## 3. 调试过程

### 3.1 先确认报错来源

先确认 LCD 上的 `FAIL T? W?? GOT XXXXXXXX` 不是 LCD 模块自己报错，而是：

- 软件: `sw/app/sdram_test/main.c`
- 显示协议: `src/rtl/periph/lcd_status.vhd`

结论：

- `T` 是测试编号
- `W` 是失败 word 索引
- `GOT` 是读回值

也确认过 `W13` / `W31` 是十六进制显示，不是十进制。

### 3.2 校验引脚映射

排查过 `par/de2extra.qsf` 中的 SDRAM 引脚分配，并逐项对照：

- `FPGA/DE2-115引脚表.xlsx`
- `doc/DE2-115_Resource_Summary.md`

结论：

- SDRAM 地址、Bank、控制线、DQ、DQM 的引脚映射是正确的。
- 引脚表不是根因。

### 3.3 给自检程序追加 UART 诊断

LCD 只能看到一个失败点，不足以继续定位，所以在 `sw/app/sdram_test/main.c` 上做了两类追加诊断：

1. 失败后打印：
   - `test`
   - `word`
   - `addr`
   - `expected`
   - `got`
2. 对失败地址追加模式诊断：
   - `0x0000FFFF`
   - `0xFFFF0000`
   - `0x00FF00FF`
   - `0xFF00FF00`

后面又追加了 `TEST2` 前 8 个 word 的 dump，用来区分：

- 某个地址固定坏
- 某个 bit 固定坏
- 连续访问时读回错位

### 3.4 接上 UART，抓到第一条关键证据

串口配置确认如下：

- 端口: `COM10`
- 波特率: `115200`
- 格式: `8N1`

第一次抓到的关键日志是：

```text
=== DE2Extra SDRAM self-test ===
base=0x01000000 words=256
init wait done
[TEST1] walking ones immediate...
<NEORV32-RTE-PANIC> [cpu0|M] Load access fault MEPC=0x0000025C MTVAL=0x01000000
[FAIL] test=1 word=0 addr=0x01000000 expected=0x00000001 got=0x80003efc
```

这条日志非常关键，因为它说明：

- 问题不只是“读出来的值不对”
- CPU 在读 `0x01000000` 时已经触发了 `Load access fault`
- 也就是说，XBUS 事务本身就没有被 SDRAM 控制器正确完成

这一步把怀疑范围从“SDRAM 数据位错误”收缩到了“总线握手/CDC/应答路径错误”。

### 3.5 第一层根因：请求/应答 CDC 有问题

原先的 `sdram_ctrl` 做法是：

- 50MHz CPU 域产生请求
- 100MHz SDRAM 域用脉冲同步和边沿检测去抓请求
- `ack` 也做了较弱的跨域返回

这套逻辑对单发访问勉强可用，但对 NEORV32 的 XBUS 不够稳，尤其是连续写后立即读、或者背靠背访问时会丢事务。

修复方向：

- 在 `src/rtl/periph/sdram_ctrl.vhd` 里改成基于 `toggle` 的请求/应答跨域
- CPU 侧先锁存完整请求，再过 CDC
- `ack` 改为稳定的 toggle 返回，而不是窄脉冲裸跨域
- 让 `ack` 返回时机延后到控制器真正空闲，而不是刚拿到数据就返回

修完这一步后，现象变成：

```text
[TEST1] walking ones immediate...
[PASS] test1
[TEST2] walking ones bulk...
[FAIL] test=2 word=1 addr=0x01000004 expected=0x00000002 got=0x00000000
```

这说明第一层问题确实被修掉了：

- `TEST1` 通过，表示“写后立刻读”已经能走通
- 失败已经不再是 `Load access fault`

### 3.6 第二层根因：读数据回传没有做正规 CDC

继续抓 `TEST2` 的 dump 后，出现了非常典型的异常：

```text
[DIAG] w0 expected=0x00000001 got=0x3d006901
[DIAG] w1 expected=0x00000002 got=0x00000002
[DIAG] w2 expected=0x00000004 got=0x00000004
[DIAG] w3 expected=0x00000008 got=0xc2009600
[DIAG] w4 expected=0x00000010 got=0x3d006910
[DIAG] w5 expected=0x00000020 got=0x00000020
```

这个模式说明：

- 不是固定地址坏
- 不是固定 byte lane 坏
- 也不是单根 DQ 线坏
- 而是有些读返回成了完全无关的垃圾值

回看 `sdram_ctrl` 代码后确认，问题在于：

- `ack` 已经跨域同步回 50MHz 了
- 但 `wb_dat_o` 仍然直接把 100MHz 域的 `rd_data_r` 裸连回 50MHz 域

也就是说，CPU 侧虽然收到了“这次读完成了”，但并不能保证同时采到的是稳定的 32-bit 读数据。

修复方向：

- 在 `src/rtl/periph/sdram_ctrl.vhd` 中给读数据增加 100MHz 持有寄存器
- 再在 50MHz 域用两级寄存器同步回来
- `wb_dat_o` 改为输出 CPU 域同步后的数据

修完这一步之后，日志变成：

```text
[TEST1] walking ones immediate...
[PASS] test1
[TEST2] walking ones bulk...
[PASS] test2
[TEST3] checkerboard...
[FAIL] test=3 word=3 addr=0x0100000c expected=0xaaaaaaaa got=0xaaaa2aaa
```

到这里为止，总线/CDC 主问题已经解决。

### 3.7 第三层根因：外部 SDRAM 时钟相移差一点

此时只剩下 `TEST3` 的一个边界错误：

```text
expected=0xAAAAAAAA
got=0xAAAA2AAA
xor=0x00008000
```

这个现象说明：

- 不是事务丢失
- 不是随机垃圾值
- 是稳定、可重复的单 bit 采样边界错误

因此把焦点转到：

- `src/ip/altpll_50_100.vhd`
- `DRAM_CLK` 相对于控制器内部 `clk_sdram` 的相位关系

相移的演进如下：

1. 旧实验值: `2496ps`
2. 中间值: `1872ps`
3. 最终稳定值: `1560ps`

最终把：

```vhdl
SDRAM_CLK_SHIFT_PS : string := "1560"
```

烧上板后，日志变成：

```text
[TEST1] walking ones immediate...
[PASS] test1
[TEST2] walking ones bulk...
[PASS] test2
[TEST3] checkerboard...
[PASS] test3
[TEST4] address-as-data...
[PASS] test4
[PASS] all tests passed
```

---

## 4. 走过的弯路

这次调试里有几次结论后来被推翻，值得单独记：

### 4.1 一度怀疑是引脚错误

因为早期 `GOT` 值里有很多高位 `1`，看起来像某几根 DQ 飘了。但在和 `DE2-115引脚表.xlsx` 核对后，证明引脚映射没有错。

### 4.2 一度怀疑是某个 byte lane / DQM 有问题

后来加了四组模式诊断：

- `low16`
- `high16`
- `byte02`
- `byte13`

这些单独诊断都能通过，说明：

- byte lane 本身是通的
- DQM 基本工作正常
- 问题出在“连续访问路径”，不是“静态单点地址”

### 4.3 一次临时最小诊断程序误伤了 LCD 协议

当时做过一版极简测试，把原来的 LCD 状态协议改坏了，导致 LCD 上出现了 `FAIL T0 W00 GOT ...` 这类误导现象。后面已经撤回，并恢复为原先 `lcd_status.vhd` 对应的协议。

---

## 5. 最终根因总结

这次不是单点 bug，而是三层问题叠加：

1. **请求/应答 CDC 不稳**
   - `sdram_ctrl` 原先抓不住 NEORV32 XBUS 的连续请求
   - 造成 `Load access fault`
2. **读数据没有跨域同步**
   - `ack` 回到了 50MHz 域，但 32-bit 读数据没有
   - 造成连续读出现 `0x3d...` / `0xc2...` 之类垃圾值
3. **SDRAM 外部时钟相位偏差**
   - 总线逻辑修好后，剩下的是硬件采样边界问题
   - 通过调整 `DRAM_CLK` 相移解决

---

## 6. 最终修改文件

### 6.1 核心修复

- `src/rtl/periph/sdram_ctrl.vhd`
  - 请求跨域改为 toggle 握手
  - `ack` 返回时机后移
  - 读数据增加 100MHz→50MHz CDC

- `src/ip/altpll_50_100.vhd`
  - 调整 `SDRAM_CLK_SHIFT_PS`
  - 最终稳定值为 `1560`

### 6.2 约束

- `constraints/de2extra.sdc`
  - 添加 `derive_pll_clocks`
  - 添加 `derive_clock_uncertainty`

### 6.3 诊断辅助

- `sw/app/sdram_test/main.c`
  - 追加 UART 失败报告
  - 追加 grouped pattern diagnostics
  - 追加 `TEST2` 前 8 个 word dump

- `tools/serial/serial_monitor.ps1`
- `tools/serial/start_serial_monitor.ps1`
- `tools/serial/stop_serial_monitor.ps1`
  - 用于常驻抓取 `COM10` 日志，避免错过复位后的第一屏输出

---

## 7. 当前稳定结论

### 7.1 当前有效的上板构建方式

```bash
MSYS_NO_PATHCONV=1 bash build.sh --flash app/sdram_test
```

或者在当前环境下直接：

```powershell
E:\Software\Scoop\apps\git\2.53.0.2\bin\bash.exe build.sh --flash app/sdram_test
```

### 7.2 当前有效的串口观察方式

启动后台监听：

```powershell
.\tools\serial\start_serial_monitor.ps1
```

停止后台监听：

```powershell
.\tools\serial\stop_serial_monitor.ps1
```

日志文件：

- `logs/serial-com10.log`

### 7.3 当前结论

- SDRAM 引脚映射正确
- Wishbone/XBUS 经 `wb_intercon` 访问 SDRAM 已经稳定
- `sdram_test` 四项测试全部通过
- 当前版本已经达到 `Phase 1` 的基本验收要求

---

## 8. 可供后续引用的关键结论

如果后面再遇到 SDRAM 异常，优先按下面顺序排查：

1. 先看 UART 日志，不要只看 LCD
2. 先判断是不是 `access fault`
3. 如果 `TEST1` 过、`TEST2` 不过，优先怀疑 CDC/连续事务路径
4. 如果 bulk 测试过了，只剩 checkerboard / address-as-data 某一位错误，优先怀疑 `DRAM_CLK` 相移
5. 引脚映射必须继续以 `FPGA/DE2-115引脚表.xlsx` 为准，不要凭印象改 QSF
