# DE2Extra 下一轮修复指引

> 更新日期: 2026-05-24  
> 适用范围: V2 当前实机工程 (`de2shell` + SDRAM + VGA/PS2/IR 集成)  
> 目的: 给下一轮修复提供统一入口，明确哪些问题还没闭环、现状是什么、目标是什么、应该先看哪些目录和参考资料

---

## 1. 当前已确认基线

这一部分不是待修复项，而是后续修复时默认应当保留的“已知好状态”。

- `sdram_ctrl` 的读回采样已稳定，根因是读捕获过早，现已后移。
- SDRAM 地址切分已按 Terasic 参考控制器对齐:
  - `bank = {addr[24], addr[10]}`
  - `row  = addr[23:11]`
  - `col  = addr[9:0]`
- 独立诊断程序 `sw/app/sdram_test/` 已验证通过:
  - `4096 words` 密集测试
  - `31` 个稀疏边界点探测
- `de2shell` 内 `memtest` 当前 4 项测试已能实机 `PASS`
- shell 心跳位编码已改回 `LEDG0` 语义，不再故意放在 `LEDG1`
- `64KB IMEM` 的 Quartus OOM 主因已经不是当前主阻塞项:
  - 旧问题是 IMEM 常量阵列综合过重
  - 当前工程已使用 `src/rtl/neorv32_imem_rom.vhd` 路线规避
- `Zfinx` 当前保持关闭，后续不要在无明确收益前重新打开

---

## 2. 相关目录索引

后续修复时，优先从这些目录找上下文，不要盲改。

### 2.1 软件入口

- `sw/app/de2shell/`
- `sw/app/sdram_test/`
- `sw/app/crypto_cli/`

### 2.2 RTL / 顶层集成

- `src/rtl/de2_115_top.vhd`
- `src/rtl/bus/`
- `src/rtl/periph/`
- `src/rtl/neorv32_wrapper.vhd`
- `src/ip/`

### 2.3 构建与约束

- `build.sh`
- `par/de2extra.qsf`
- `constraints/de2extra.sdc`

### 2.4 当前规划与验收文档

- `doc/implementation_plan.md`
- `doc/phases/phase3-integration.md`
- `doc/phases/phase5-sdram-gui.md`
- `doc/de2shell-module-acceptance.md`
- `doc/reference/init-sequence-current-shell.md`
- `doc/编译烧录前必看.md`
- `doc/issue.md`

### 2.5 板卡与 Terasic 参考资料

- `DE2-115_v.3.0.6_SystemCD/`
- `doc/reference/terasic-cdrom-analysis.md`
- `doc/phases/phase1-sdram-debug-report.md`
- `E:\Main\JuniorII\NonExam\FPGA\DE2-115引脚表.xlsx`

---

## 3. 建议优先级

按当前状态，建议修复顺序如下:

1. `dashboard / board_status` 演示模式闭环
2. `memtest` 展示收敛，把 SDRAM 回归测试并回 shell 入口
3. VGA 实显与画廊频道
4. `life` 手动编辑模式正式并入
5. IR end-to-end 验收
6. Quartus 编译并行度与构建链整理
7. `crypto_cli` 的 Zk* 加速与 TRNG 统计收尾

---

## 4. 待修复项详单

## 4.1 `dashboard / board_status` 还不是正式“统一演示模式”

### 现状

- `dashboard` 已不再是纯占位页，但当前仍主要是状态监视和 board ownership demo。
- `Phase 3` 文档已经把它定位为统一状态层的一部分，但还没达到“统一接管 13 个实验演示”的程度。
- 目前 shell 常驻页、子程序页、dashboard 页对 LCD / HEX / LED 的接管边界还不够清晰。

### 修复目标

- 建立一个真正的“实验演示模式”:
  - LCD 显示当前实验名 / 频道名 / 状态
  - HEX 给出稳定且有解释的状态码
  - LEDG/LEDR 区分心跳、瞬时动作、实验状态
  - SW 提供常驻配置
  - KEY 提供短时操作
- 明确 shell 空闲态与子程序运行态的板级状态编码规范，避免每个程序随意写 GPIO

### 相关代码

- `sw/app/de2shell/board_status.c`
- `sw/app/de2shell/board_status.h`
- `sw/app/de2shell/dashboard.c`
- `sw/app/de2shell/main.c`
- `src/rtl/de2_115_top.vhd`
- `src/rtl/periph/lcd_status.vhd`

### 相关文档

- `doc/phases/phase3-integration.md`
- `doc/de2shell-module-acceptance.md`
- `doc/reference/init-sequence-current-shell.md`

### 验收口径

- shell 空闲时，LCD / HEX / LED 含义固定且可解释
- 进入 `dash` 后，dashboard 能明确接管板级显示
- 从 `dash` 退回 shell 或切换子程序后，接管关系不乱

---

## 4.2 `memtest` 入口还没完全收敛成最终形态

### 现状

- `de2shell` 中的 `memtest` 当前仍是“4 项测试 + PASS/FAIL 展示”版本。
- 新增的稀疏边界探测和更强的回归覆盖目前只在独立 `sw/app/sdram_test/` 中。
- 也就是说:
  - 壳内入口适合演示
  - 独立测试适合诊断
  - 但两者还没合成一套统一方案

### 修复目标

- 保留 `memtest` 作为唯一对外展示入口
- 展示内容收敛为:
  - 逐项列出测试用例
  - 最后统一输出 `ALL PASS`
  - 失败时给出稳定的 `test/word/exp/got`
- 视空间决定是否把“稀疏边界探测”并入 shell 版:
  - 若并入，建议放为 `Case 5`
  - 若不并入，至少在文档中说明 `memtest` 与 `sdram_test` 的分工

### 相关代码

- `sw/app/de2shell/memtest.c`
- `sw/app/sdram_test/main.c`
- `src/rtl/periph/sdram_ctrl.vhd`

### 相关文档

- `doc/phases/phase3-integration.md`
- `doc/de2shell-module-acceptance.md`
- `doc/phases/phase1-sdram-debug-report.md`

### 验收口径

- `memtest` 在 shell 中运行，串口与 VGA 输出一致
- PASS / FAIL 信息不互相覆盖
- `q` 返回 shell，`r` 重测正常
- 若保留独立 `sdram_test`，需在文档中明确它是“维修模式”而不是“日常演示模式”

---

## 4.3 VGA 实显链路和 Exp6 / Exp7 画廊频道还没闭环

### 现状

- VGA 文字终端与 HAL 已接入工程，仿真和串口镜像可用。
- 但正式 VGA 实物显示链路仍属于待确认项。
- 文档里还把 Exp6 / Exp7 作为“等 VGA 线后补”的项目。

### 修复目标

- 完成 VGA 实物显示验收:
  - 文字页
  - 状态栏
  - 子程序页
  - 清屏 / 光标 / 双页行为
- 在此基础上补齐 Exp6 / Exp7 的画廊频道或等效展示页

### 相关代码

- `src/rtl/periph/vga_text_terminal.vhd`
- `sw/app/de2shell/vga_hal.c`
- `sw/app/de2shell/main.c`
- `src/rtl/de2_115_top.vhd`
- `par/de2extra.qsf`

### 相关资源

- `DE2-115_v.3.0.6_SystemCD/`
- `E:\Main\JuniorII\NonExam\FPGA\DE2-115引脚表.xlsx`

### 相关文档

- `doc/phases/phase2b-vga-terminal.md`
- `doc/phases/phase3-integration.md`
- `doc/de2shell-module-acceptance.md`

### 验收口径

- 上电进入 shell 后，VGA 实屏与串口内容一致
- `help / memtest / crypto / life / dash` 页面切换无花屏
- Exp6 / Exp7 至少有一个可稳定展示的正式入口

---

## 4.4 `life` 手动编辑模式需求还没有正式收口

### 现状

- 当前 `life.c` 已支持:
  - 方向移动
  - 编辑/运行切换
  - 空格置生灭
  - 图案载入
- 但仓库里还存在一个独立的 `conway_ed.c`，且未注册进 shell。
- 这说明“编辑态能力”已经部分并入 `life.c`，但整体方案还没完成统一。

### 修复目标

- 在 `life.c` 与 `conway_ed.c` 之间二选一，不要长期双轨:
  - 要么继续增强 `life.c`
  - 要么把 `conway_ed.c` 正式接入并替换
- 最终保留一个统一入口，满足:
  - 方向键/WASD 选格
  - 空格切换生灭
  - Enter 运行
  - Pause/step 可控
  - HUD 显示模式与坐标

### 相关代码

- `sw/app/de2shell/life.c`
- `sw/app/de2shell/conway_ed.c`
- `sw/app/de2shell/main.c`

### 相关文档

- `doc/phases/phase3-integration.md`
- `doc/de2shell-module-acceptance.md`
- `doc/phases/phase2b-vga-terminal.md`

### 验收口径

- shell 中只有一个正式 `life` 方案
- 编辑与运行切换逻辑清晰
- 文档不再同时描述两个并行实现

---

## 4.5 IR 功能还没有做完真正的端到端验收

### 现状

- IR 硬件与 shell 路径已经接入。
- 文档中仍把 IR 标成 `🟡`，核心问题不是“没代码”，而是“缺实板闭环验收”。
- 另外 `dashboard` 还没有补“最近一次 IR 码值显示”。

### 修复目标

- 完成 CH1-CH7 / CH+/CH- 的实机切换验收
- 验证子程序 `ir_input` 与全局映射优先级
- 在 dashboard 中补一个最近 IR 命令的可视化状态

### 相关代码

- `src/rtl/periph/ir_nec_decoder.vhd`
- `src/rtl/periph/ir_nec_wb.vhd`
- `sw/app/de2shell/main.c`
- `sw/app/de2shell/dashboard.c`

### 相关文档

- `doc/phases/phase3-integration.md`
- `doc/de2shell-module-acceptance.md`
- `doc/reference/init-sequence-current-shell.md`

### 验收口径

- 遥控器切频道有明确板上反馈
- 串口 / VGA / LCD 状态一致
- dashboard 能看到最近一次 IR 事件

---

## 4.6 Quartus 编译并行度仍锁在单核

### 现状

- 当前 QSF 明确写死:
  - `par/de2extra.qsf:18`
  - `set_global_assignment -name NUM_PARALLEL_PROCESSORS 1`
- 这就是每次编译日志里出现“发现 14 个处理器但只用 1 个”的原因。
- 这里的“核心数”是 Quartus 使用的上位机 CPU 并行度，不是 SoC 的 RISC-V 核数。
- 之前不敢放开并行度，主要是为了避开旧版 IMEM 常量阵列导致的综合内存压力。

### 修复目标

- 把“Quartus 并行度”从“功能修复问题”中独立出来，作为构建链调优项
- 在确认主机内存足够后，评估改为:
  - `8`
  - 或 `10`
- 同步更新文档，避免后续再把“编译核数”和“CPU 多核”混淆

### 相关代码 / 配置

- `par/de2extra.qsf`
- `build.sh`
- `src/rtl/neorv32_imem_rom.vhd`
- `src/rtl/neorv32_wrapper.vhd`

### 相关文档

- `doc/编译烧录前必看.md`
- `CLAUDE.md`
- `README.md`

### 验收口径

- 明确记录改并行度前后的编译时间变化
- 若改为 `8` 或 `10`，需确认:
  - 不重新引入 OOM
  - 不引入不稳定的随机编译失败

---

## 4.7 `crypto_cli` 的 Phase 2a 收尾项还没做完

### 现状

- 基线 CLI 已可用
- 但文档中仍把以下内容标为未完成:
  - Zk* 加速实现
  - 软件 vs Zk* 基准对比收口
  - TRNG 统计验证

### 修复目标

- 完成 `bench` 中各算法的真实 Zk* 路径
- 保证监视器和 CLI 的指令编码说明一致
- 至少补一个基础 TRNG 统计测试

### 相关代码

- `sw/app/crypto_cli/`
- `sw/app/de2shell/crypto.c`
- `sw/app/de2shell/monitor.c`
- `src/rtl/neorv32_wrapper.vhd`

### 相关文档

- `doc/phases/phase2a-crypto-cli.md`
- `doc/de2shell-module-acceptance.md`
- `doc/implementation_plan.md`

### 验收口径

- `crypto> bench` 输出不再是“半成品表格”
- 与 `monitor` 的 AES / SHA / SM4 指令演示口径一致
- 不重新启用 `Zfinx`

---

## 5. 暂不建议现在处理的项

这些不是不能做，而是当前不应与上面的修复项混做。

### 5.1 SoC 多核

- 当前文档已把它移到:
  - `doc/phases/extra-multicore.md`
- 当前不建议把“Quartus 编译并行度”与“NEORV32/VexRiscv 多核”混为一谈
- 现阶段优先先把 V2 的单核系统收口

### 5.2 V3: SDRAM 执行 + GUI + FreeRTOS

- 路线文档已经升级到:
  - `doc/phases/phase5-sdram-gui.md`
- 但该路线明确说明:
  - 不阻塞当前 V2
  - 需要在 V2 基线稳定后再切换

---

## 6. 下一轮修复前建议先做的检查

每次开始下一轮修复前，先快速核对这几项:

1. 当前烧进去的是 `app/de2shell` 还是 `app/sdram_test`
2. `par/de2extra.qsf` 里的 `NUM_PARALLEL_PROCESSORS` 是否仍为 `1`
3. `src/rtl/periph/sdram_ctrl.vhd` 中地址切分是否仍保持 Terasic 对齐版本
4. `src/rtl/neorv32_wrapper.vhd` 是否仍保持 `RISCV_ISA_Zfinx => false`
5. 若改 QSF 引脚，必须对照 `E:\Main\JuniorII\NonExam\FPGA\DE2-115引脚表.xlsx`

---

## 7. 简短结论

如果只看“下一轮最值得修的东西”，优先做这三件:

1. 把 `dashboard / board_status` 做成正式的统一演示模式
2. 把 `memtest` 与 `sdram_test` 的分工收敛清楚
3. 把 VGA 实显和 IR end-to-end 验收补齐

做完这三件，V2 阶段的“系统像样程度”会明显提升，后面再切 V3 才不至于在基础层反复返工。
