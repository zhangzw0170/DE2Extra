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
- `de2shell` 内 `memtest` 当前 5 项测试已能实机 `PASS`
- shell 心跳位编码已改回 `LEDG0` 语义，不再故意放在 `LEDG1`
- `64KB IMEM` 的 Quartus OOM 主因已经不是当前主阻塞项:
  - 旧问题是 IMEM 常量阵列综合过重
  - 当前工程已使用 `src/rtl/neorv32_imem_rom.vhd` 路线规避
- `Zfinx` 当前保持关闭，后续不要在无明确收益前重新打开
- `crypto bench` 已完成一次实板跑通，软件/`Zk*` 对比表与 TRNG 统计均有输出
- `SW[17:0]` 板测已恢复正常，根因是 `par/de2extra.qsf` 此前漏掉了 `SW[15:0]` 约束
- `KEY[3:1]` 在 `dashboard` 中现已可正常观察，根因不是引脚，而是该页之前会被全局 KEY 快捷键抢占
- `IR` 接入后造成的 UART 假死已经定位:
  - 问题不在 UART/JTAG 外设本身
  - 根因是 `sw/app/de2shell/main.c` 里首版 `timer_wb` 轮询会阻塞等待第一下红外边沿
  - 该死等已移除，串口输入已恢复
- `IR` 遥控器码表已确认不能再按旧 `CH1-CH7 / CH+/CH-` 假设处理:
  - `FPGA/Exp/Exp10/Exp10实验指导书原文.md` 表 6-16 才是当前这只遥控器的准确信息
  - 例如 `0x1A` 在这只遥控器上实际对应 `CH+`
  - 歧义根因是：表 6-16 用 `0..23` 给物理按键排位编号，而不是沿用遥控器表面的印刷键名
  - 这也是此前映射错乱的根因：shell 一度把“表内序号”误当成了“数字键标签”

### 1.1 2026-05-24 实板修复记录

1. `memtest` 实板确认
   五项测试 `Walking-1 immediate / bulk / checkerboard / address-as-data / sparse boundary` 全部 `PASS`。
2. `crypto` 实板确认
   `bench` 能正常输出软件基线、`Zk*` 加速比以及 `TRNG statistics`。
3. `SW` 修复
   `dashboard` 只能看到 `SW17:16` 的根因是 `par/de2extra.qsf` 之前只约束了 `SW[17:16]`；补完 `SW[15:0]` 后恢复正常。
4. `KEY` 修复
   `KEY[3:1]` 实际一直在 `gpio_in(20:18)` 里，但 `dashboard` 页面先被全局快捷键逻辑解释成“切程序 / 回 shell / 重刷页面”；给 `dashboard` 禁用全局 KEY 热键后已恢复原始观测。
5. `UART` 回归修复
   接入 IR 后“串口不能输入”的根因不是串口线路，而是主循环最前面的 `handle_ir_events()` 阻塞等待 IR 事件，导致永远跑不到 `uart_kbhit()`；现已修掉。

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

1. VGA 实显与画廊频道
2. IR end-to-end 验收
3. dashboard / board_status / crypto bench 实板确认
4. 构建链与文档持续整理

---

## 4. 待修复项详单

## 4.1 `dashboard / board_status` 代码已闭环，剩一次实板确认

### 现状

- `dashboard` 已不再是纯占位页，当前会显示 SW / KEY / GPIO / uptime / 最近 IR 命令。
- shell 与未主动声明状态的子程序现在都走统一 fallback 编码，不再复用陈旧 GPIO 低位。
- `life` 与 `dashboard` 这类主动声明状态的程序，会继续保有自己的板级状态字。

### 修复目标

- 下一次实板确认时重点检查:
  - shell 空闲态的 `READY` 编码
  - `dash` 页面主动接管后的 `LIVE` 编码
  - 从 `dash` 退回 shell / 切换到其它程序后，接管关系是否稳定

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

## 4.2 `memtest` 已收敛，独立 `sdram_test` 保留为维修模式

### 现状

- `de2shell` 中的 `memtest` 已更新为 5 项测试:
  - walking-1 immediate
  - walking-1 bulk
  - checkerboard
  - address-as-data
  - sparse boundary probes
- `sw/app/sdram_test/` 继续保留更大覆盖率的 UART-only 诊断路径，定位为“维修模式”。
- shell 版现在支持统一 `ALL PASS` 汇总、失败时显示完整 `test/word/addr/exp/got`，并支持 `r` 重测。

### 修复目标

- 当前这部分代码已收口，后续只需在下一次板测时顺手确认输出与文档一致。

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
- `sdram_test` 明确作为“维修模式”保留

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

## 4.4 `life` 手动编辑模式已正式并入主路径

### 现状

- 当前正式入口就是 `life.c`。
- 已支持:
  - 方向键 / WASD 移动
  - 编辑 / 运行切换
  - 空格置生灭或单步
  - `Enter` 运行，`E` 返回编辑
  - HUD 显示模式与光标坐标
- `conway_ed` 不再作为并行实现保留在当前验收路径里。

### 修复目标

- 当前这部分不再作为待修项，后续只保留 `life` 单一路径维护。

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
- `dashboard` 现在已经能显示最近一次 IR 命令。
- 当前剩余问题已经从“有没有接进去”收缩成“事件链路为什么没真正触发”。
- 最近一次回归里，`main.c` 曾尝试改走 `timer_wb` 做软件 NEC 解码；这条路先后暴露了两类问题:
  - 首版实现会阻塞等待第一下 IR 边沿，直接卡死 UART
  - 计时窗口按 NEC 下降沿间隔写的，但 `timer_wb` 当前捕获的是上升沿，软件层等于又造了一套未经板测的新解码器
- 因此当前更合理的主路径应优先回到 `ir_nec_wb` 这条已有硬件解码寄存器链路上，再做板测闭环。

### 修复目标

- 完成 Exp10 遥控器数字键 `1-7`、`0/RETURN`、`CH+/CH-` 的实机切换验收
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

## 4.6 Quartus 编译并行度问题已脱离当前阻塞项

### 现状

- 当前 `par/de2extra.qsf` 已是:
  - `set_global_assignment -name NUM_PARALLEL_PROCESSORS 8`
- 因此“仍锁在单核”已经不是当前真实问题。
- 后续这里只保留为构建链调优与文档一致性检查项。

### 修复目标

- 保持文档与 QSF 当前设置一致
- 后续若继续调大到 `10`，再单独记录编译时间和内存占用变化

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

- 文档不再错误宣称其为“单核编译”
- 若继续调大到 `10`，需确认不重新引入 OOM 或随机失败

---

## 4.7 `crypto_cli` 剩余项已缩到一次实板确认

### 现状

- 基线 CLI 已可用。
- `de2shell/crypto.c` 和 `crypto_cli` 中的 `bench` 已经接入真实 Zk* 路径:
  - AES-128
  - SHA-256
  - SHA-512
  - SM4
  - SM3
- 当前还没闭环的主要是下一次实板确认:
  - cycle / speedup 数值
  - TRNG 单比特统计输出

### 修复目标

- 保证监视器和 CLI 的指令编码说明一致
- 下次板测时顺手确认 `bench` 输出格式、速度提升表和 TRNG 统计输出

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

- `crypto> bench` 输出格式稳定
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

1. 把 VGA 实显和 Exp6 / Exp7 画廊频道补齐
2. 把 IR end-to-end 验收补齐
3. 顺手做一次 dashboard / board_status / crypto bench 的实板确认

也就是说，除去 VGA 和 IR，V2 当前剩下的主要就是一次板测确认，而不是新的大块代码开发。
