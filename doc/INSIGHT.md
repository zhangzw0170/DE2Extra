# INSIGHT — 从"点亮 LED"到"一台完整的计算机"

> 基于 git 历史（2026-05-21 ~ 2026-06-04，149 次提交）梳理项目发展历程。

## 一个被忽略的约束

FPGA 原理课的常规做法是用 VHDL 写一个计数器/状态机，在开发板上验证时序，交一份仿真波形。DE2-115 有 114,480 个逻辑单元、128MB SDRAM、VGA、PS/2、音频 CODEC、红外接收器——一次实验只用到其中几百个 LE。

如果只是用一个更贵的芯片做同样的事，和用仿真器没有本质区别。

---

## Day 1: 让 RISC-V 跑起来 (05-21)

**`5ce2046` feat: initialize DE2Extra project with NEORV32 RISC-V submodule**

第一个 commit 就做了两件事：引入 NEORV32 作为 git submodule，写了一份完整的 DE2-115 资源手册（pin 表、PLL 规格、外设清单）。这时候连一行 VHDL 都没写——整个硬件设计是 NEORV32 自带的。

计划文档里提到了 FreeRTOS + LVGL，目标 720p VGA，甚至考虑过达芬奇 A7Pro 板子兼容。这些后来都没实现，但可以看出从第一天起，目标就不是"做一个实验"，而是"建一个平台"。

**`1ae6fb2` feat: Phase 0 minimal system — CPU running on DE2-115**

同一天晚些时候，Phase 0 完成：
- `de2extra_pkg`: 共享类型、常量、hex_to_seg7
- `clk_rst_gen`: 时钟直通 + 复位同步器
- `neorv32_wrapper`: 55 个 generic 的 CPU 配置封装（RV32IMC + Zk* 密码扩展 + XBUS + OCD）
- `seg7_mapper`: 7 段数码管译码器
- `de2_115_top`: 板级顶层，GPIO→LEDR/HEX 映射
- Docker 交叉编译环境（riscv-none-elf-gcc）
- Hello World 程序（LED 跑马灯 + UART 心跳）

**板子验证通过**：LEDR 计数 + HEX 显示确认 CPU 存活。从 commit 到上板，一个晚上。

16 个文件，1494 行新增。这是整个项目里最关键的一步——CPU 跑起来了，后面所有东西都建立在这个基础上。

---

## Day 2: 修 Pin (05-22)

**`7746fe1` fix: correct LEDR[11-17] pin assignments and separate GPIO bit ranges**

LEDR[11]-LEDR[17] 的 pin 分配错了。之前的 pin（F14/E14/C15/C16）导致 I/O bank 电压冲突。对着 DE2-115 引脚表逐个修正。

同时把 GPIO 位宽从 18 扩到 32，分开了 LEDR（bit 0-17）和 HEX（bit 16-31）的范围。还加了 `zifencei` 到 MARCH——NEORV32 的 crt0.S 需要它。

**教训**：Pin 分配错了 Quartus 不会报错，编译照样通过，但板子上就是不对。这个教训后来写进了 CLAUDE.md："Pin table is truth"。

---

## Day 3: 一天搭完骨架 (05-23)

这是项目里最疯狂的一天——**从早到晚 18 个 commit**，Phase 1 到 Phase 4 全部启动。

### 上午：Phase 2a — 密码学终端

**`c9c9c35` feat(phase2a): crypto CLI with AES/SHA/SM4/SM3/TRNG via UART**

纯 C 裸机程序，所有算法都通过了标准测试向量：
- AES-128 ECB（NIST FIPS-197）
- SHA-256 / SHA-512（NIST FIPS-180-4）
- SM4（GB/T 32907）
- SM3（GB/T 32905）
- TRNG（NEORV32 硬件驱动）

双模式编译：LOCAL_BUILD（host gcc 测试）和 NEORV32（Docker 交叉编译，text 13556B，占 IMEM 41%）。

Zk* 内联汇编标注已经写好，为后续硬件加速做准备。

### 中午：Phase 2b — VGA 文字终端 + PS/2 键盘

**`30e764d` feat(phase2b): VGA text terminal + PS/2 keyboard controller (VHDL)**

VGA 80×25 文字终端（640×480@60Hz）：
- 复用 Exp6 已验证的 VGA 时序生成器
- 双页 text buffer（2×2000 words，M9K BRAM）
- 8×16 ASCII font ROM（128 chars，2048 entries）
- 逐字符 RGB332 前景色 + 全局背景色
- 光标闪烁 (~1Hz) + 页面切换 + 清屏控制

PS/2 键盘控制器：
- 复用 Exp8 已验证的 ps2_sync + ps2_receiver
- 16-entry FIFO + overflow 检测
- IRQ 输出用于 data-ready 中断

VGA 地址 `0xF0000000`，PS/2 地址 `0xF0002000`。直接 XBUS 地址解码，还没用到 Wishbone intercon。

### 下午：Phase 3 prep — 各种程序

一口气加了六个模块：
- **NEC IR 解码器**：从 Exp10 搬过来
- **LED 模式 + 数字钟**：从 Exp2/3 搬过来
- **系统 dashboard**：SW/KEY/IR 实时状态渲染
- **Snake 贪吃蛇**：UART 终端版
- **Conway 生命游戏**：B3/S23 规则，滑翔机+枪

### 下午：Phase 3 — 统一 Shell 框架

**`f212a5b` feat(phase3): add unified shell framework with VGA HAL**

这是整个项目的**第二个关键转折点**（第一个是 CPU 跑起来）。

在这之前，每个程序是独立的 `.c` 文件，有自己的 `main()`。在这之后，所有程序通过 `program_t` 结构体注册到 shell：

```c
typedef struct {
    const char *name;
    void (*init)(void);
    void (*update)(void);
    void (*input)(char c);
    void (*finish)(void);
} program_t;
```

用户视角从"运行一个硬件"变成了"使用一台计算机"。打 `snake` 就玩蛇，打 `crypto` 就做加密，打 `help` 看所有命令。

**`d9ca02a` feat(phase3): add Exp1/4/5/12 as shell programs**

实验也变成了 shell 命令。不需要重新编译上传，直接在 shell 里输入实验编号就切换。

### 晚上：Phase 1 SDRAM + Phase 4 规划

**`137a15c` feat: save phase1 sdram bring-up results**

SDRAM 控制器上板通过。128MB 空间可用。这个 commit 有 43 个文件变更，8860 行新增——主要是 Quartus 工程文件和 SDRAM 相关 RTL。

然后开始写分析文档：
- **RTOS 选型分析**：对比 FreeRTOS、Zephyr、RIOT，结论是 FreeRTOS（最小侵入、NEORV32 已有 RISC-V port）
- **RTOS 迁移成本分析**：估计 4 天，不追求完美
- **Phase 4 规划**：硬件加速器（Conway、PONG、NTT）+ 音频

### 深夜：Phase 4 RTL 一口气写完

三个硬件加速引擎同一天完成：
- **Conway 硬件引擎**（`conway_engine.vhd`）：并行邻居计算
- **PONG 硬件引擎**（`pong_engine.vhd`）：球/挡板物理
- **NTT 模块**（`modmul`、`butterfly`、`twiddle ROM`、`ntt_top`）：ML-KEM-512 数论变换

这些 RTL 当天还上不了板——需要等 V3 的 Wishbone intercon 和 SDRAM 基础设施。但架构已经定型。

### 深夜：PS/2 键盘基线

**`f1e4e25` fix(ps2): add keyboard led sync and document phase2b**

PS/2 键盘 CapsLock/NumLock/ScrollLock LED 同步。caps 切换时发 `0xED` + LED mask 命令，键盘 LED 跟着亮灭。

**`f8ec6dc` docs: update VGA blocker — need VGA→HDMI converter (not HDMI→VGA cable)**

VGA 显示器还没搞定——买错了线。需要 VGA→HDMI 转换器（不是 HDMI→VGA 线），周一才能到。

---

## Day 4: V2 上板验证 (05-24)

**`3ed8cbc` Integrate and validate de2shell on hardware**

19 个文件，11820 行新增。这是 V2 的完整上板验证：

- SDRAM 自检 5 项全部通过（Walking-1s、Checkerboard、Address-as-data）
- Shell 命令解析正常（help、hello、crypto、ps2、snake、life、monitor、dash、memtest、expdemo）
- IR 遥控切频（数字键 1-9 启动程序，CH+/CH- 顺序切换）
- LCD 16×2 显示 shell 状态
- HEX/LED 心跳可见，证明主循环还在跑

VGA 还看不到（转换器没到），但 UART 侧全部验证通过。

后续 commit 修了一串小 bug：
- monitor SHA-256 指令编码写错
- monitor AES demo 命令格式不对
- 加了命令历史和退格编辑
- 显示静态光标
- board_status 和 IR shell 控制集成

### 下午：V3 雏形

**`3ade958` feat(v3): add SDL2 framebuffer HAL and NTT accelerator**

已经在为 V3 做准备了：
- SDL2 帧缓冲 HAL（本地测试用）
- NTT 加速器 RTL（`ntt_sdf.vhd`，DIF NTT/INTT，q=3329，N=256，Barrett reduction）
- NTT Python 验证脚本全部 PASS

**`021fbfa` feat(ntt): add C driver with SW reference and HW MMIO**

NTT C 驱动双模式：LOCAL_BUILD 走纯软件参考实现，NEORV32 走硬件 MMIO。delta、round-trip、convolution 全部 PASS。

**`1144909` feat(de2os): add FreeRTOS app with SDRAM execution**

V3 的核心：
- FreeRTOS-Kernel 作为 git submodule
- 三个任务：t_gui (pri 3)、t_crypto (pri 2)、t_input (pri 1)
- 链接目标 SDRAM (`0x01000000`)
- 交叉编译验证通过：text=6384B，entry=0x01000000

**`ff8b64d` feat(de2os): add ICACHE support and deployment documentation**

ICACHE 支持和部署文档。boot mode 0 的完整流程第一次被记录下来。

**`4f6091a` fix(de2os): revert to de2shell defaults and add switch script**

切回去——de2os 和 de2shell 不能同时编译，需要 switch script 在两个配置间切换。

### 晚上：ExpDemo 统一

**`a19f344` Document expdemo as unified experiment entry**

原来的 Exp1/4/5/12 是四个独立命令。现在统一成 `expdemo` 一个入口，通过数字键+Enter 选择实验。

**`cb65a5d` Stabilize expdemo hardware channel routing**

13 个实验的硬件通道路由稳定。ExpDemo 多路复用器（`expdemo_wb.vhd`）通过 Wishbone 总线控制实验切换。

---

## Day 5: V2 冻结，V3 定型 (05-25)

### 凌晨：大批重构

**`4a06ed5` feat(rtl): update all peripherals and top-level for expdemo/NTT/SDRAM**

13 个文件，9921 行新增。所有外设 RTL 更新：
- ExpDemo 通道 mux、KEY0 release、6/7 blocking
- NTT_SDF 重写为可综合的定点 VHDL
- SDRAM 控制器：burst FSM + async FIFO CDC
- wb_intercon：cti/tag 信号直通
- neorv32_wrapper：暴露 xbus_cti_o/xbus_tag_o

**`b3345d5` feat(rtl): add course lab modules, adapters and new peripherals**

45 个文件，6540 行新增。11 个实验适配器 + 原始实验 VHDL 模块。还有 async_fifo（8-deep 32-bit 双时钟 CDC FIFO）、intc_wb、timer_wb、lcd_wb 等。

**`6b253c8` feat(sw): de2shell firmware — unified shell with expdemo and crypto**

19 个文件。完整的 de2shell 固件：多频道程序分派、IR 频率切换、crypto Zk* 加速、dashboard、monitor、ps2、life、ntt。

**`7c78f4c` feat: Quartus projects, deploy scripts, de2os top entity, CLAUDE.md**

12 个文件，10034 行新增。独立的 `de2os_top.vhd`（V3 顶层）、Quartus 工程、部署脚本、CLAUDE.md。

### 上午：V2 完成

**`0f76ccf` feat: V2 complete — VGA verified, bugs fixed, docs archived**

VGA 显示器终于接上了（VGA→HDMI 转换器到了）：
- 修复 SYNC_N 极性（绿屏消失）
- 修复底部边距重复状态栏
- 所有 H2.1-12 验收项通过

软件方面：GFX 绘图库、GUI 控件库、Win 3.0 桌面（SDL2 验证通过，NEORV32 待移植）、PS/2 解码器提取、帧缓冲 HAL。

V2 阶段文档归档到 `doc/archive/v2phase/`。验收 192/213 ✅。

### 下午：V3 架构定型

**`e83d693` docs: V2 frozen, V3 active — de2os only, PS/2 keyboard primary input**

V2 冻结。V3 工作重心明确：de2os（FreeRTOS + SDRAM + PS/2 键盘 + VGA 像素 GUI）。

**`92a9b6b` docs: V3 plan re-evaluated — 47h→30h**

重新评估 V3 工期：47 小时 → 30 小时（~17h 已完成）。新增 FreeRTOS+CLI 任务（替换手写 strcmp 解析器）。

**`c37b1e8` docs: V3 plan corrected against codebase reality**

逐节审计 V3 计划，修正与实际代码不符的部分：bootloader 不是手写的（用 NEORV32 内置的）、VGA pixel ctrl 是独立实体（不在 vga_text_terminal 里）、framebuffer 基址 0x01000000→0x01800000。

**`065ca31` feat(rtos): integrate FreeRTOS+CLI and runtime resource monitoring**

FreeRTOS+CLI 集成（MIT 许可，2 文件组件）。新增 stats/heapstat/cpustat 命令。FreeRTOS 子模块锁定到 V11.3.0。

**`c8e231c` test(rtos): add standalone CLI test harness (31/31 pass)**

FreeRTOS+CLI 独立测试：stub 头文件、mock 命令、自动化断言。31/31 全通过。

### 晚上：字体 + 蛇 + 文档

**`d681cd9` feat(font): extend VGA font ROM to full CP437 (256 chars)**

VGA 字库从 128 字符扩展到完整 CP437（256 字符）。写了 `gen_font_rom.py` + CP437_8x16.bin 从真实位图字体生成 VHDL package 和 C 头文件。字库 ROM 从 2048→4096 字节，仍然只用 1 个 M9K。

这步很关键——后面 Snake 的 box-drawing 边框（`│`、`─`、`┌`、`┐`）和 Conway 的全角字符都依赖扩展字库。

**`2ab8838` feat(vga+snake): VGA HAL scroll/vblank, full-screen snake with CP437 border**

VGA HAL 加了 scroll region、clear_line、vblank sync（轮询 REG_STATUS bit 0）。VGA_ROWS 从 25 扩到 30。Snake 扩展到 78×27 网格填满整个 80×30 屏幕，用 CP437 box-drawing 字符画边框。

---

## Day 6: VGA 调试 + ExpDemo (05-26)

**`3e22160` docs: V3 phase plans (v3p1-v3p5) + full documentation refresh**

17 个文件，3647 行新增。写了 9 个 V3 阶段计划文档（v3p1-v3p5）。刷新了 15+ 份文档里的总线地址映射（13 个从站：PS/2→0xF0008000、NTT→0xF000F000 等）。

**`91c6adf` fix: upload abort on failure, QSF pins+MIF, exp_uart_txd mux, snake box char**

修了一堆集成问题：
- 上传脚本失败时 raise RuntimeError 而不是静默继续
- Quartus QSF 加了 sin_data.mif 和 SW[0..15] pin 分配
- exp_uart_txd 信号声明 + mux（expdemo 激活时 UART 输出切到实验）
- Snake 的 `║`（0xBA）改成 `│`（0xB3）

**`b8eb89b` fix(lcd): add shell LCD reinit on expdemo exit**

ExpDemo 退出后 LCD 需要重新初始化——加了 `p_lcd_shell_reinit` 进程，检测 expdemo_active 下降沿，发 1ms 复位脉冲。

---

## Day 7-8: RTL 集成 (05-29 ~ 05-30)

### 05-29: NTT/PONG/Conway RTL 真正接进系统

**`dee2312` feat(v3): integrate NTT/PONG/Conway RTL, register all CLI commands, add pxtest diagnostic**

24 个文件。这是 V3 功能最集中的一次集成：

RTL（de2os_top.vhd）：
- NTT/PONG/Conway 从 stub 升级为真实实例化
- INTC s7 总线挂死修复（ack loopback 替代 tied '0'）
- Quartus 编译通过：0 error，262 warnings，timing clean（setup +2.4ns）

固件（de2shell_rtos/main.c）：
- 注册 conwayhw、ponghw、ntt、twm、life、monitor 命令
- pxtest：5 阶段 VGA 像素模式诊断（test pattern + SDRAM 回读 + debug 寄存器）
- PS/2 竞争修复：排除 PROG_WIN30/PROG_PONG_HW 的 t_uart_input 轮询

Bug 修复：
- crypto.c：`trng_bytes()` 加 `trng_available()` 检查防止无限 busy-loop
- ntt.c：NEORV32 路径用直接 MMIO 替代 ntt_a[] 数组

### 05-30: Audio synth + ChromaShader + Snake 2P

**`50050bf` feat(v3): integrate audio synth RTL + C driver**

RTL：wb_intercon s11 从站，de2os_top synth_engine 实例化，6 个 AUD/I2C pin。7 个 VHDL 综合修复（shift_left 括号、i2s_tx end if、dds_core 类型不匹配、fm_operator 乘积宽度、MIF 路径）。Quartus 0 error，62% LEs。

C 驱动（synth.c）：88 音符 tuning table，PS/2 双轨钢琴键盘（16+10 键），3xOSC/DX7 模式切换，八度移位，预设加载。CLI 命令 `synth` 注册（第 21 个命令）。

**`35191d4` feat(v3): add Exp6/7 VGA test patterns, fix I2C SDA tri-state**

新增 VGA 测试图案生成器（640×480@60Hz，8 种颜色模式）。Exp6 静态、Exp7 动画。VGA 输出 mux（exp > pong > pixel > text）。

I2C SDA 三态修复：`I2C_SDAT` 从 `out` 改为 `inout`，防止总线竞争。

**`aa38d3e` feat(v3p3b): add AES-128/SHA-256 step-through visualization**

暴露 crypto 内部函数（aes_sub_bytes、aes_shift_rows、sha256_round 等），实现逐步可视化。AES：41 个快照跨 10 轮，带状态矩阵变化高亮。SHA-256：65 个快照，工作变量网格。

**`46637d3` feat(v3): ChromaShader RTL integration + PS/2 virtual keycode TUI support**

ChromaShader（噪声地形探索游戏）RTL 集成。QuestaSim 19/19 pass。

更重要的是 PS/2 虚拟键码系统：
- 22 个 VK 常量（F1-F12、方向键、导航键）
- 输入门控修改使非 ASCII 键到达程序
- Snake 和 ChromaShader 加了方向键支持（除 WASD 外）

**`80d2c70` feat(v3p6): Snake 2P mode + global F1/F10 + remove Q quit**

Snake 完全重写：
- 1P/2P 模式选择（两页菜单）
- P1: WASD（绿 `o`），P2: 方向键（青 `=`）
- 共享食物、碰撞检测（自撞/互撞/头碰头）
- F10 全局退出（替代 Q——Q 和 WASD 冲突，太容易误触）

F1 全局帮助：在 `prog->input()` 之前拦截，输出帮助文本。
F10 全局退出：在 `prog->input()` 之后检查，程序可以先做清理。

所有 13 个程序的 Q 退出全部移除。

---

## Day 9: GPU + VGA PLL + TWM 像素模式 (06-01)

**`081ce67` feat(v3p6): GPU 2D accelerator + VGA PLL fix + TWM pixel mode working**

这是 V3 里视觉效果最显著的一个 commit：

- **GPU 2D 加速器**（`gpu_2d.vhd`）：FILL rect 通过 SDRAM burst-write。WB slave s12 @ 0xF0015000。CPU 逐像素写 framebuffer 每帧 ~2 秒完全不能交互，GPU burst 写降到 ~3ms，加速比 ~400x。
- **VGA PLL 修复**：25MHz 像素时钟从 toggle flip-flop 改为 PLL c3 输出（专用全局时钟网络）。输出寄存器改用 falling_edge。
- **sdram_ctrl**：第 4 条 burst 路径给 GPU 写，async FIFO 给 VGA 读。
- **vga_pixel_ctrl**：RGB565 双行缓冲，80 bursts/scanline。
- **TWM 像素模式在物理显示器上首次成功显示**（2026-06-01）。

pxtest 数据通路验证：
- SDRAM 回读：0/2560 错误（CPU 32-bit write/read 完美）
- Framebuffer 采样：gradient 数据与预期匹配
- VGA burst read：valid_word/burst_req ≈ 8
- TWM 30 秒稳定运行

**`d2d5a7e` refactor: migrate sw/app/de2shell → sw/lib shared library**

97 个文件，4523 行删除。把所有源码从 `sw/app/de2shell/` 迁移到 `sw/lib/` 作为共享库。删除 V2 时代的 app 目录（de2os、game_life、game_snake、hello、ir_test 等）。

**`ae26444` feat: remove PONG, add selfcheck, tick 1ms, shell idle HEX/LED display**

- 删除 PONG 外设（RTL + testbench + C 驱动）——12 个 WB 从站
- 新增 selfcheck（POST）：6 项自检（SDRAM、WB bus、PS/2、TRNG、BuildInfo、FB）
- FreeRTOS tick 100Hz → 1000Hz（1ms 精度）
- Shell 空闲板级显示：HEX5-4=heap%（BCD），HEX3-0=uptime（hex），LEDG/LEDR raw hex

---

## Day 10-12: 打磨 (06-02)

### Bug 修复 + Conway VHDL 重写

**`07e150e` feat: conway HW grid fix, F1/F10 help system, life.c removal**

Conway VHDL 网格行读取修复：加 addr 5（cols 32-63）和 addr 6（cols 64-79）寄存器。之前只返回前 32 列，后面全是乱码。

F1 帮助叠加层加到 snake、conway、synth。帮助自动暂停游戏。

删除软件 Conway（life.c），重命名 conwayhw→conway。

**`b4770c2` feat: Conway 64x25 grid, release report**

Conway VHDL 缩减到 64×25（2-word 行读取，`ramstyle="logic"` 用 LE 寄存器而非 M9K）。C 驱动重写。加了 SYSU LaTeX 发布报告。

**`5bb8e87` fix: VHDL address decoding (Conway/NTT), R29 scroll, UX polish**

RTL 地址解码修复：
- Conway：`wb_adr_i(4:2)`→`(2:0)`，intercon 已经发 word 地址
- NTT：`x"400"`→`x"100"` ctrl，`x"404"`→`x"101"` status

还加了 pForth 解释器（pForth V2.1，完整的 Forth 语言运行时）。

**`223eeff` fix: NTT address decode, Conway partial refresh, synth UART piano**

wb_intercon NTT 地址提取 bug：之前把基地址位 `[13:12]` 传进了寄存器偏移，导致所有寄存器比较失败。Conway 改用 shadow buffer 做局部刷新减少闪烁。Synth 加了 ASCII 钢琴映射（A-; 白键，W/E/R/T/Y/I/O 黑键）+ VGA 音符显示。

### UART 角色重设计

**`7652e38` feat: UART serial role redesign — debug-only, CLI dual-path, Ctrl+C**

UART 从"第二 VGA"变成调试通道：
- 禁用 VGA 串口镜像（serial_mirror_enabled=0）
- CLI 文本程序（crypto/ntt/forth/info/monitor/hello）通过 vga_set_uart_text() 输出纯文本
- Shell 双路：提示符/回显/命令输出同时到 VGA 和 UART
- Ctrl+C (0x03) 强制退出当前程序

### Synth VHDL 五连修

**`1b0e14c` fix(synth): WM8731 I2C register addressing, I2C STOP, I2S lrck_edge**

5 个 bug：
1. CFG 数组：所有 10 个寄存器写入的地址位 `[15:9]` 都是 0，全写到了寄存器 0 而不是 0-9
2. Active 寄存器（CFG[9]）：是 x"0000"（reg 0 写入），应该是 x"1201"（reg 9 ACTIVE bit）——codec 从未被激活
3. Master mode（reg 7）：数据是 0x01（slave），应该是 0x12（master）。BCLK/LRCK 是 FPGA 输入，所以 WM8731 必须驱动它们
4. I2C STOP 条件：无条件 `state <= S_BIT_LOW` 覆盖了 phase 2 ACK 后的 `state <= S_STOP1`
5. i2s_tx lrck_edge：缺少 else 子句导致脉冲永远为高，移位寄存器每个时钟周期都重新加载

**`c6ac749` fix: TRNG selftest — use data_avail() instead of get_fifo_depth()**

`neorv32_trng_get_fifo_depth()` 返回的是配置的 FIFO 大小（永远是 4），不是当前填充量。两个 wait 循环变成了 `while(4 < 2)` 和 `while(4 < 4)`——永远 false，永远不等待。从空 FIFO 读出来全是零，r1==r2，报"no entropy"。

---

## Day 13: 功能收尾 + NTT 测试 + 硬件精简 (06-03)

### 凌晨：Promo 物料 + Conway 修复

**`cccfef7` docs: add promotional architecture diagram and presentation slides**

交互式架构图（HTML+CSS，自适应布局）和演示文稿 PPT（reveal.js，5 页幻灯片）。用代码生成而非截图，方便后续更新。

**`e5ff326` docs: add banner SVG and rewrite bilingual READMEs**

Banner SVG（深色主题，6 个统计指标），README 中英双语重写，badge 标签。

**`631cd87` fix: conway cursor blink, finish crash, TRNG seed, partial refresh**

Conway 四连修：
1. 光标闪烁导致数据竞争——在刷新循环中停止闪烁
2. 游戏结束时 `finish()` 崩溃——空指针解引用
3. TRNG 种子初始化时机错误
4. 局部刷新边界条件

### 上午：Synth + TWM + 多程序修复

**`01985e1` feat: synth audio output, TWM serial commands, conway/snake/ntt fixes**

多个程序的一轮集中修复：synth 首次有音频输出、TWM 加了串口命令支持、conway/snake/ntt 各有小修。

### 下午：Cryptoviz 上板 + LCD 重设计

**`e19a6f6` fix: LCD display redesign — correct prog_id mapping, unified Line1, per-program Line2**

LCD 显示逻辑重写：Line 1 统一显示 "DE2Extra Status"，Line 2 按当前程序显示不同内容。之前的 prog_id 映射有错，导致 LCD 显示的程序名和实际运行的程序不对应。

**`62fa7a2` feat: cryptoviz board verification, NTT RTL fix, local SDL2 build, V2 cleanup**

Cryptoviz 上板验证通过——AES/SHA 的逐步可视化在物理 VGA 显示器上正确渲染。同时修了 NTT RTL 的一个问题，加了本地 SDL2 构建支持，清理了 V2 时代的残留文件。

### 晚上：NTT 测试套件 + 硬件精简

**`646810a` feat: add NTT automated test suite (test_ntt.py)**

NTT Python 自动化测试套件——DIF/DIT 正变换/逆变换、round-trip 一致性、卷积验证。为后续调试提供了可靠基线。

**`2ee5d9d` feat: remove NTT/synth HW from synthesis, SW NTT fallback, 10 active peripherals**

关键决策：**NTT 和 Synth 硬件从综合中移除**。两个模块的 RTL 代码保留在仓库中，但不再参与 Quartus 编译。NTT 改为纯软件实现，Synth 禁用。原因：
- NTT：255/256 元素不匹配的根因未定位，硬件不可靠
- Synth：WM8731 音频输出有背景噪音，缺少专业音频测试设备验证

FPGA 利用率从 ~55% 降到 **~47%**（53.5K / 114.5K LEs），时序裕量更宽。

Wishbone 总线从 12 active 变为 **10 active**，2 个从站改为 stub ack（返回全零 + 立即 ack）。

**`2d751a1` fix: stub ack for removed NTT/synth Wishbone slaves, remove selfcheck probe**

wb_intercon 中 NTT/Synth 的 slave port 改为 stub ack。selfcheck 不再探测这两个地址。

**`b997c20` feat: TWM desktop background changed to 8-color vertical bars (Exp7 mode 01)**

TWM 桌面背景改为 8 色竖条（复用 Exp7 的 VGA 测试图案 mode 01），比纯色更有视觉效果。

---

## Day 14: 跨平台 CLI + Release (06-04)

### 凌晨：Release 文档准备

**`f0071ef` docs: v0.3 release — update all docs, promo, add quick-start guide**

v0.3 发布文档准备：README 快速入门、promo 数据更新（144 commits 等）、构建指南。

**`4d4fedd` docs: update all repository facade for v0.3 release**

Banner、架构图、PPT 的数据一致性更新。

**`f808854` fix: promo polish — AES 100+x, Display font size, remove highlight chips**

Promo 细节打磨：AES 加速比改为 "100+x"、Display 字体大小调整、移除 highlight chips。

**`fe71d8d` chore: save accumulated progress — docs, CLAUDE.md, sw/lib, build info**

保存累积进度：CLAUDE.md 更新、sw/lib 代码整理、build info 同步。

### 上午：跨平台 CLI 工具

**`67d18a7` feat: add cross-platform CLI tool (run/de2extra.py)**

替代 `deploy_de2shell_rtos.sh` 的跨平台 Python CLI：

| 子命令 | 功能 | 耗时 |
|--------|------|------|
| `sw-build` | Docker 交叉编译固件 | ~25s |
| `sw-upload` | UART 上传 + 软重启 | ~20s |
| `hw-build` | Quartus 综合 | ~15min |
| `hw-flash` | JTAG 烧录 SOF | ~11s |

自动检测：串口（pyserial 扫描）、Quartus 安装路径（全盘搜索）、Docker。环境变量覆盖：`DE2OS_COM`、`QUARTUS_ROOTDIR`。

同时修了 `upload_de2os.py` 的 bootloader 检测 bug——no-wait 模式下 `wait_for_prompt_with_abort()` 每 0.23s 发空格，阻止 bootloader 完成自动启动序列。改为 `wait_for_prompt()` 静默等待。

所有 4 个子命令在真实硬件上验证通过。

### 下午：Release 完成

**`cd1a9f0` docs: v0.3 release — AI declaration, disclaimer, NEORV32 patches, promo data**

最终发布提交：
- AI 使用声明（GLM 5.1, DeepSeek V4, GPT 5.4 / Claude Code, DeepSeek TUI, Codex）
- 硬件免责声明
- NEORV32 v1.13.1 本地补丁文档（6 项 bootloader 修改）
- `ver` 命令新增 `Version: v0.3`
- Promo 数据更新：148 commits，~45s 增量部署

GitHub Release `v0.3` 发布，中英双语 Release Notes，43 commits 分类汇总。

---

## 八个决策速览

| # | 决策 | 日期 | 解决什么问题 |
|---|------|------|-----------|
| 1 | RISC-V 软核替代手工状态机 | 05-21 | FPGA 只用了 1% 资源，实验之间没有关联 |
| 2 | 统一 shell 框架先建壳 | 05-23 | 每个新功能都要从头搭框架 |
| 3 | 课程实验变成 shell 命令 | 05-23 | 实验做完就忘，无法展示集成效果 |
| 4 | 引入 FreeRTOS + boot mode 0 | 05-25 | IMEM 64KB 放不下大程序，改 C 代码不再触发 Quartus 重编译 |
| 5 | 硬件加速器针对 CPU 瓶颈 | 05-23/06-01 | CPU 逐像素写帧 2 秒，NTT 运算慢两个数量级 |
| 6 | VGA 像素模式 + TWM | 06-01 | 文字终端和串口输出没有视觉区分度 |
| 7 | 统一操作逻辑，打磨体验 | 06-02 | 各程序操作不一致，Bug 影响可用性 |
| 8 | 精简未完成硬件，专注可靠性 | 06-03 | NTT/Synth 硬件不可靠，占用 FPGA 资源且无法验证 |

## 时间线

```
Day 1  (05-21)  NEORV32 上板，UART Hello World，Docker 交叉编译
Day 2  (05-22)  Pin assignment 修复（LEDR[11-17] I/O bank 冲突）
Day 3  (05-23)  18 commits: SDRAM + Crypto CLI + VGA 终端 + PS/2 键盘
                + Shell 框架 + 13 实验 + Conway/PONG/NTT RTL
                + RTOS 选型分析 + Phase 4 规划
Day 4  (05-24)  V2 上板验证（UART 侧全通过），FreeRTOS 迁移开始
                NTT C 驱动，de2os 雏形
Day 5  (05-25)  V2 冻结 + VGA 验证，V3 定型（FreeRTOS+CLI 集成）
                CP437 256 字符字库，Snake 全屏 78×27
Day 6  (05-26)  V3 阶段计划文档，ExpDemo 路由，LCD reinit 修复
Day 7-8 (05-29/30) NTT/PONG/Conway RTL 集成，Audio synth + ChromaShader
                + Exp6/7 VGA 测试图案 + Snake 2P + F1/F10 全局键
Day 9  (06-01)  GPU 2D 加速器，VGA PLL 修复，TWM 像素模式首次上板
                源码迁移到 sw/lib 共享库，selfcheck POST
Day 10-12 (06-02) 程序打磨：F1/F10 统一帮助系统，Conway 64×25 ramstyle="logic"
                + toggle_cell，NTT 地址解码修复，UART 角色重设计
                Synth WM8731 5 连修，TRNG selftest 修复
                Conway 局部刷新，文档整理归档
Day 13 (06-03)  15 commits: Cryptoviz 上板验证，NTT 测试套件
                NTT/Synth 硬件从综合移除（10 active peripherals）
                Stub ack + SW fallback，TWM 8 色竖条背景
                Promo 物料（架构图 + PPT + Banner + 双语 README）
Day 14 (06-04)  6 commits: 跨平台 Python CLI 工具（de2extra.py）
                AI 使用声明 + 免责声明 + NEORV32 补丁文档
                Promo 数据更新，v0.3 GitHub Release 发布
```

14 天，149 次提交。从零到一个有 10 个活跃 Wishbone 外设、22 条 CLI 命令、FreeRTOS 4 任务、VGA 像素 GUI、7 小时+ 长稳无崩溃的完整系统。

## 一句话总结

用 FPGA 做一个能容纳许多功能的系统，而不是用 FPGA 实现某个功能。

具体做法：RISC-V 软核统一平台，Wishbone 总线 + 统一 shell 让新功能只需注册，实验变成 shell 命令而不是交完就忘，boot mode 0 分离硬件和软件迭代，硬件加速器针对 CPU 实际瓶颈，像素 GUI 提供视觉区分度，统一操作逻辑让系统从"能用"变成"好用"。

这不是把 FPGA 课做得更复杂，是换了一个让复杂度有意义的组织方式。
