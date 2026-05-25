# de2os 时序约束状态

> 日期: 2026-05-25
> 适用工程: `par/de2os/`

## 结论

在本次检查前，`de2os` 的 Quartus STA 报告并不能代表真实设计时序状态。

根因：

- `par/de2os/de2os.qsf` 引用了 `SDC_FILE ../constraints/de2extra.sdc`
- 但 `par/constraints/de2extra.sdc` 当时并不存在
- 结果主时钟约束没有被读入

直接证据见旧 `par/de2os/de2os.sta.rpt`：

- `SDC File List` 只有 `jtag_uart` 自带约束
- `CLOCK_50` 被识别成时钟，但 `without an associated clock assignment`
- `PLL cross checking found inconsistent PLL clock settings`
- `Unconstrained Clocks = 23`
- Fmax / setup / hold 只剩 `altera_reserved_tck`

因此：

- 旧 `de2os.sta.rpt`
- 旧 `de2os.sta.summary`

都不能继续作为 `de2os` 的 sign-off 依据。

## 当前已修复

已恢复工程实际引用的共享约束文件：

- [par/constraints/de2extra.sdc](/E:/Main/JuniorII/NonExam/FPGA/DE2Extra/par/constraints/de2extra.sdc:1)

当前这份约束包含：

1. `CLOCK_50` 20ns 基准时钟
2. `derive_pll_clocks`
3. `derive_clock_uncertainty`
4. `DRAM_CLK` 10ns 时钟
5. `clk_50m` 与 `clk_sdram` 的异步分组
6. 一组基础 SDRAM 输出延迟约束
7. `KEY[*]` 和 TRNG ring oscillator 的 false path

这意味着下一次重新跑 STA 时，至少应该能看到：

- `clk_50m`
- PLL 派生出来的 100MHz 时钟
- `DRAM_CLK` / `clk_sdram` 相关路径

而不是只有 `altera_reserved_tck`。

## 当前仍然缺什么

这份 SDC 还不是完整 sign-off 级别，至少还有这些缺口：

### 1. SDRAM 输入时序没有建模

当前文件只有：

- `set_output_delay` 给地址 / 命令 / DQM

但还没有：

- `DRAM_DQ[*]` 的 `set_input_delay`
- 读返回相对内部采样时钟的完整板级建模

这意味着：

- 现阶段可以先恢复主时钟分析
- 但不能把它当作最终的板级 SDRAM I/O 完整约束

### 2. `DRAM_CLK` 被同时 `derive_pll_clocks` 和 `create_clock`

当前共享 SDC 延续了旧写法：

- 先 `derive_pll_clocks`
- 再对 `DRAM_CLK` 端口显式 `create_clock`

这在某些工程里是可接受的，但也可能和自动派生时钟发生重复/竞争解释。后续如果新 STA 仍然报 PLL/clock 相关 warning，需要优先检查这里。

### 3. `de2os_top` 与 `de2_115_top` 共用一份约束

这有好处，也有风险：

- 好处：不容易两边漂移
- 风险：共享 SDC 里如果有层级路径，必须同时兼容两个顶层

目前这份 SDC 基本只用端口级约束，所以风险不大。

## 下一次 STA 的判定标准

重新跑 `par/de2os/` 后，至少需要满足下面几条，旧报告才算真正被替换掉：

1. `SDC File List` 里出现 `../constraints/de2extra.sdc`
2. `Clocks` 表里不再只有 `altera_reserved_tck`
3. `CLOCK_50` 不再显示为 `Unconstrained`
4. `PLL cross checking found inconsistent PLL clock settings` 若仍出现，需要单独处理
5. `Unconstrained Clocks` 数量应明显下降
6. 主分析结果应该覆盖 `clk_50m` / `clk_sdram`，而不是只覆盖 JTAG TCK

## 实际工作建议

当前优先级建议如下：

1. 先重新跑一次 `par/de2os/` STA 或完整编译
2. 读新的 `de2os.sta.rpt`
3. 如果主时钟恢复正常，再决定是否补：
   - `DRAM_DQ` 输入延迟
   - 更严格的 SDRAM I/O 时序模型
   - VGA / SDRAM / PLL 的更细化 generated clock 约束
