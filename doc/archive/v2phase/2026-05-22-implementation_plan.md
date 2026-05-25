# DE2Extra 实施计划 — 总纲

> 日期: 2026-05-22 | 更新: 2026-05-24 | 状态: Active | Deadline: 2026-06-15
> 归档: v1 (SoC+FreeRTOS+LVGL) → v2 (VGA 终端合并版) → v3 (SDL2 + NTT + de2os) → `archive/`

## 背景

基于 NEORV32 (RISC-V) 的 FPGA 项目，目标平台 DE2-115 (Cyclone IV E)。
从"一次性跑 13 个 Exp 模块"的想法演变而来，最终方向是带硬件密码学加速的 RISC-V 终端系统。

### 当前进度

- **Phase 0**: NEORV32 @50MHz 上板，UART/GPIO/LED/HEX/LCD 已验证 ✅
- **Phase 1**: SDRAM + `wb_intercon` 已上板跑通，`sdram_test` 四项全过 ✅
- **Phase 2a 基线**: `crypto_cli` 纯 C 版已上板跑通，RS-232 (`115200 8N1`) 下 `help/info/aes/sha/sm/trng/bench` 已实机验证，LCD 已切换为 `DE2Extra Crypto / UART CLI READY` ✅
- **Phase 2a 收尾**: Zk* 指令加速版、纯 C vs Zk* 性能对比、TRNG 统计验证实板确认 ✅ (AES 107.6x, SM4 1.7x, TRNG 50.24%) — 详见 `phases/phase2a-crypto-cli.md`
- **Phase 2b**: VGA 终端 + PS/2 键盘源码完成，PS/2 已接入顶层 (wb_intercon s2 + ps2_irq → mext_irq_i)；PS/2 扫描码、扩展键解析、LCD 键盘回显、键盘 Lock 灯双向同步均已实板验证 ✅；VGA 画面待 VGA→HDMI 有源转换器到货 (预计 5/26 周一) ⏳
- **Phase 3**: Unified Shell 框架就位 (14 程序注册: hello/memtest/crypto/snake/life/dash/info/monitor/exp1/4/5/12 + ps2 + 全局 shell)；IR 遥控切频实板修复 ✅；dashboard 状态层接入 ✅ (串口验收通过)；Zk* bench 实板验证 ✅；NTT C 驱动 (LOCAL_BUILD 验证) ✅；ExpDemo 硬件实例化 ✅；当前差 VGA 实显与实板联调 🟡
- **V3 扩展**: SDL2 帧缓冲 HAL (LOCAL_BUILD) + NTT 加速器 (硬件禁用, C 驱动完成) ✅；de2os (FreeRTOS, SDRAM 执行, ICACHE_EN=false 基线可启动) 🟡
- Zk* 密码学 ISA + TRNG 已启用，Docker 工具链就绪

### 核心决策

- 不做 GUI 框架 (FreeRTOS/LVGL)，改为纯硬件 VGA 文字终端
- FPU 推迟评估，Zfinx 够用
- 优先级: 密码学平台 > 多模块演示 > 教学展示

---

## 路线图

```
Phase 1           Phase 2a + 2b (并行)          Phase 3
总线+SDRAM   ──→  2a: 密码学终端(C)            ──→  集成+多模块
(硬件基础)         2b: VGA终端+PS/2(VHDL)        (联调+整合)
```

| Phase | 内容 | 产出 | 详见 |
|---|---|---|---|
| **1** | SDRAM timing 修复 + Wishbone interconnect | 可靠的总线基础 | `phases/phase1-bus-sdram.md` |
| **2a** | 密码学 UART 终端 (C 软件) | AES/SHA/SM4/SM3/TRNG + CLI | `phases/phase2a-crypto-cli.md` |
| **2b** | VGA 文字终端 + PS/2 键盘 (VHDL 硬件) | 80×25 彩色终端 + Conway | `phases/phase2b-vga-terminal.md` |
| **3** | 2a+2b 集成 + 已验收模块挂载 | 完整终端系统 | `phases/phase3-integration.md` |
| **4** | 硬件加速器 + 音频 | Conway + PONG + NTT (C 完成/硬件禁用) + I2S | `phases/phase4-hardware-accelerators.md` |
| **Extra** | 多核研究储备 | VexRiscv+NEORV32 大小核 / NEORV32 SMP | `phases/extra-multicore.md` |

## 时间线

| 周次 | 工作内容 |
|---|---|
| 5/22-5/23 | ~~Phase 1: SDRAM timing + wb_intercon~~ 完成 |
| 5/23 | ~~Phase 2a: Crypto CLI 纯 C 完成~~ |
| 5/23 | ~~Phase 2a 基线上板验证完成~~ (RS-232 + LCD 状态) |
| 5/23 | ~~Phase 2b: VGA/PS2 源码完成~~ |
| 5/23 | ~~Phase 3: Shell + hello/memtest 加入, 12 程序注册~~ |
| 5/24-6/01 | Phase 2b + Phase 3: PS/2/IR/总线接入 ✅ + VGA 实板联调 (**VGA→HDMI 线 5/26 到货后补显示验证**)；de2os ICACHE debug ✅ |
| 6/02-6/08 | Phase 2a Zk* 加速 + Phase 3: 集成 + 双输出 + ExpDemo 联调 + Exp6/7 画廊 |
| 6/09-6/13 | Phase 3 (续): VGA 实显联调 + 演示页 |
| 6/14-6/15 | 收尾: 文档、演示准备 |
| 6/15+ | Phase 4 (音频/SD) / Extra (多核): 暑期研究项目 |

## 资源预算

| 模块 | LEs | M9K | DSP |
|---|---|---|---|
| NEORV32 + SDRAM + LCD (现有) | ~4,000 | ~45 | ~15 |
| wb_intercon (s0-s8) | ~200 | 0 | 0 |
| VGA 终端 (Phase 2b) | ~300 | ~10 | 0 |
| PS/2 键盘 (Phase 2b) | ~150 | ~1 | 0 |
| NTT 加速器 (禁用) | ~2,000 | ~4 | ~64 |
| ExpDemo (11 实验适配器) | ~500 | ~2 | 0 |
| de2os 扩展 (LCD+Timer+INTC) | ~300 | ~2 | 0 |
| **合计** | **~7,450** | **~64** | **79** |
| **板载** | 114,480 | 432 | 266 |
| **占用率** | **~4%** | **~13%** | **~6%** |

## 风险

| 风险 | 缓解 |
|---|---|
| SDRAM timing 修复不彻底 | 降频保证基本功能 |
| 字库 ROM .mif 初始化问题 | 从开源项目复制已知字库 |
| PS/2 协议时序丢码 | FIFO 缓冲 + 重试 |
| 6/15 时间不足 | Phase 1-2 是核心，Phase 3 按时间灵活裁剪 |
