# INSIGHT — 从"点亮 LED"到"一台完整的计算机"

> 基于 git 历史（2026-05-21 ~ 2026-06-01，104 次提交）梳理项目发展历程。

## 一个被忽略的约束

FPGA 原理课的常规做法是用 VHDL 写一个计数器/状态机，在开发板上验证时序，交一份仿真波形。DE2-115 有 114,480 个逻辑单元、128MB SDRAM、VGA、PS/2、音频 CODEC、红外接收器——一次实验只用到其中几百个 LE。

如果只是用一个更贵的芯片做同样的事，和用仿真器没有本质区别。

## 第一个决定：把板子变成平台，而不是实验载体

2026-05-21，第一个 commit：`initialize DE2Extra project with NEORV32 RISC-V submodule`。

引入 RISC-V 软核替代手工状态机，FPGA 的角色从"实现一个功能"变成了"运行一个系统的硬件"。每个外设不再是独立实验，而是系统的一个组件；软件可以在 C 语言层面迭代；课程实验复用同一个 Wishbone 总线接口。

5 月 21 到 22 日两天只做了一件事：让 NEORV32 在 DE2-115 上跑起来，50MHz，UART 输出 "Hello World"。

## 第二个决定：先建壳，后填充

5 月 23 日，一天之内搭完了 Phase 1-3 的骨架：SDRAM、Crypto CLI、VGA 文字终端 + PS/2 键盘、统一 shell 框架。

关键转折点是 commit `feat(phase3): add unified shell framework with VGA HAL`。在这之前，蛇、康威生命游戏、LED 模式各自是独立程序。在这之后，它们变成了 shell 里的命令——用户视角从"运行一个硬件"变成了"使用一台计算机"。

"先建壳"的好处是后续每个新功能只需要注册一个 `program_t` 结构体和几行命令分派。到 5 月 23 日晚，已经有了一个能用的终端系统：能打字、能跑蛇、能显示 LED、能切实验。5 月 24 日上板验证通过。

## 第三个决定：把实验变成 shell 命令，而不是交完就忘

Commit `feat(phase3): add Exp1/4/5/12 as shell programs` 把实验集成进 shell。后来（5 月 30 日）发展为 ExpDemo 统一多路复用器：13 个实验共享同一套 VGA/键盘接口，通过编号切换。

这样做之后，实验不再是"交作业就完"的任务，而是系统的一部分。评分标准也跟着变了——从"代码对不对"变成了"集成的系统好不好用"。

老师说"有点子"，很大程度上是因为这个转变。一个单独的计数器和一个 shell 里的计数器，技术含量可能相同，但给评委的观感完全不同。

## 第四个决定：瓶颈在哪，战场就在哪

V2 在 5 月 25 日冻结。原因不是硬件做完了，而是软件成了瓶颈：IMEM 只有 64KB 放不下更大的程序，裸机单循环无法同时处理键盘输入和 VGA 刷新，没有优先级调度做不了后台任务。

5 月 23 日写了 `RTOS selection analysis` 和 `RTOS migration cost analysis` 两个分析文档。结论是引入 FreeRTOS，但只花 4 天做迁移，不追求完美，先跑起来再迭代。

V3 的另一个关键决策是 boot mode 0：IMEM 只放 2KB bootloader，主程序通过 UART 下载到 SDRAM 执行。这把软件迭代周期从分钟级（每次改代码都要重跑 Quartus ~4 分钟）降到秒级。没有这个决策，后面 GPU、TWM、Snake 2P 这些需要大量软件调试的功能根本做不了。

## 第五个决定：硬件加速是因为软件跑不动了

5 月 23 日同一天写了 `Phase 4 plan: hardware accelerators (Conway, PONG, NTT)`，并且当天就完成了三个引擎的 RTL。看起来像是"顺便多做几个硬件"，但动机很具体：

- Conway 硬件引擎：CPU 遍历 256×256 网格每帧只能算几代，硬件并行化后可以到 60fps
- NTT 加速器：ML-KEM-512 的数论变换，CPU 做一轮 ~10ms，硬件 ~100μs
- GPU 2D（6 月 1 日）：CPU 逐像素写 framebuffer 每帧 ~2 秒完全不能交互，GPU burst 写降到 ~3ms，加速比 ~400x

如果 FPGA 只是做软件能做的事，它没有存在价值。软件碰到墙的时候，硬件才有意义。

## 第六个决定：像素 GUI 提供视觉区分度

V3 推进了 VGA 像素模式（6 月 1 日）。之前 VGA 只用于 80×30 文字终端，和串口输出没有本质区别。像素模式加上 TWM 窗口管理器、RGB565 色彩、GPU 加速渲染，在展示时的冲击力远大于文字终端。

## 六个决策速览

| # | 决策 | 日期 | 解决什么问题 |
|---|------|------|-----------|
| 1 | RISC-V 软核替代手工状态机 | 05-21 | FPGA 只用了 1% 资源，实验之间没有关联 |
| 2 | 统一 shell 框架先建壳 | 05-23 | 每个新功能都要从头搭框架 |
| 3 | 课程实验变成 shell 命令 | 05-23 | 实验做完就忘，无法展示集成效果 |
| 4 | 引入 FreeRTOS + boot mode 0 | 05-25 | IMEM 64KB 放不下大程序，改 C 代码不再触发 Quartus 重编译（仍需 ~20 分钟） |
| 5 | 硬件加速器针对 CPU 瓶颈 | 05-23/06-01 | CPU 逐像素写帧 2 秒，NTT 运算慢两个数量级 |
| 6 | VGA 像素模式 + TWM | 06-01 | 文字终端和串口输出没有视觉区分度 |

## 时间线

```
Day 1 (05-21)  NEORV32 上板，UART Hello World
Day 2 (05-22)  Pin assignment 修复
Day 3 (05-23)  SDRAM + Crypto + VGA + PS/2 + Shell + 13 实验 + Conway/PONG/NTT RTL
Day 4 (05-24)  V2 上板验证，FreeRTOS 迁移开始
Day 5 (05-25)  V2 冻结，V3 架构定型，FreeRTOS 集成
Day 6 (05-26)  VGA 调试，ExpDemo 路由，Conway/PONG 仿真通过
Day 7-8 (05-29/30) NTT/PONG/Conway RTL 集成，Audio synth，ChromaShader
Day 9 (05-30)  Snake 2P，PS/2 TUI 虚拟键码
Day 10 (06-01) GPU 2D，VGA PLL 修复，TWM 像素模式上板
Day 11 (06-01) 文档清理，v0.2 发布
```

11 天，104 次提交。从零到一个有 13 个 Wishbone 外设、22 条 CLI 命令、FreeRTOS 多任务、VGA 像素 GUI 的完整系统。

## 一句话总结

用 FPGA 做一个能容纳许多功能的系统，而不是用 FPGA 实现某个功能。

具体做法：RISC-V 软核统一平台，Wishbone 总线加统一 shell 让新功能只需注册，实验变成 shell 命令而不是交完就忘，boot mode 0 分离硬件和软件迭代，硬件加速器针对 CPU 实际瓶颈，像素 GUI 提供视觉区分度。

这不是把 FPGA 课做得更复杂，是换了一个让复杂度有意义的组织方式。
