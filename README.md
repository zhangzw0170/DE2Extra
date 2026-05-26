# DE2Extra — NEORV32 RISC-V 全外设终端系统

[English](README.en.md) | 中文

> 让 DE2-115 开发板变成一台完整的计算机：RISC-V CPU + VGA 终端 + PS/2 键盘 + SDRAM + 密码学加速 + 课程实验多路复用

## AI 使用声明

本项目在开发过程中使用了以下大语言模型辅助：[DeepSeek V4](https://chat.deepseek.com/)、[GLM 5.1](https://chatglm.cn/)、[GPT 5.4](https://chat.openai.com/)。所有 AI 生成内容均经过人工审查。

## 参考资源

- [NEORV32 RISC-V Processor](https://github.com/stnolting/neorv32) — 本项目使用的 RISC-V 软核
- [FreeRTOS](https://www.freertos.org/) — de2shell_rtos 使用的实时操作系统内核
- [DE2-115 System CD](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=167&No=506) — Terasic 官方例程与参考资料

## 项目概览

在 DE2-115 (Cyclone IV E) 上运行 [NEORV32](https://github.com/stnolting/neorv32) RISC-V 软核，通过自定义 Wishbone 外设驱动板载硬件。V2 (de2shell) 已冻结验收通过；V3 (de2shell_rtos) 为当前主线。

```
┌─────────────────────────────────────────────────────┐
│  de2shell_rtos — FreeRTOS 多任务终端 (V3 主力)       │
│  CLI 16 条命令: hello / memtest / crypto / snake /    │
│  life / info / expdemo / twm / ps2 / vgadump / ...  │
├─────────────────────────────────────────────────────┤
│  de2shell — 裸机多频道终端 (V2 冻结, 不再更新)        │
├─────────────────────────────────────────────────────┤
│       NEORV32 RISC-V 软核 (~4000 LUTs)              │
│       RV32IMC + Zicsr + Zicntr + Zk* 密码扩展        │
├─────────────────────────────────────────────────────┤
│  自定义 VHDL 外设 (Wishbone 从站)                     │
│  SDRAM | VGA | PS/2 | LCD | IR | NTT | ExpDemo |    │
│  Conway | PONG | Audio synth | BuildInfo             │
├─────────────────────────────────────────────────────┤
│       DE2-115 FPGA (Cyclone IV E, 114K LEs)          │
└─────────────────────────────────────────────────────┘
```

## 硬件平台

**主平台**: Terasic DE2-115 (`EP4CE115F29C7`)

- **FPGA**: Cyclone IV E, 114,480 LEs, 266 硬件乘法器, 4 PLL
- **存储**: 128MB SDRAM, 2MB SRAM, 8MB Flash, SD 卡槽
- **显示**: 16×2 LCD, 8 个七段数码管, 27 个 LED (9G+18R), VGA (8-bit/通道 DAC)
- **通信**: RS-232, PS/2 ×2, 红外接收, USB 2.0, 千兆以太网 ×2
- **音频**: WM8731 24-bit CODEC
- **输入**: 4 个按键, 18 个拨码开关

引脚参考: [`DE2-115_pin_table_backup.md`](DE2-115_pin_table_backup.md)

## CPU 配置

NEORV32 (v1.13.1) 作为 git submodule 引入。

- **ISA**: RV32IMC + Zicsr + Zicntr + Zbkb/Zbkc/Zbkx + Zknd/Zkne/Zknh/Zksed/Zksh
- **频率**: 50 MHz
- **存储**: 64KB IMEM (M9K) + 16KB DMEM (M9K) + 128MB SDRAM (外部)
- **内置外设**: UART (115200), GPIO (32-bit), TRNG, CLINT, OCD debugger
- **密码加速**: AES, SHA-256/512, SM3/SM4 硬件指令 (Zk*)
- **外部总线**: Wishbone, 支持 burst 传输 (cti/tag)
- **许可**: BSD-3-Clause (submodule)

本地修改记录: [`doc/reference/neorv32-patches.md`](doc/reference/neorv32-patches.md)

## 外设模块

所有自定义外设通过 `wb_intercon` 以 Wishbone 从站形式挂载，使用统一寄存器接口。

| 模块 | 地址 | 说明 | 状态 |
|---|---|---|---|
| `sdram_ctrl` | `0x01000000` | 128MB SDRAM 控制器, burst 支持, 异步 FIFO CDC | ✅ 上板通过 |
| `vga_text_terminal` | `0xF0000000` | 80×30 彩色文字终端, CP437 全 256 字符, 像素模式 (SDRAM FB) | ✅ 上板通过 |
| `ps2_controller` | `0xF0008000` | PS/2 键盘 + FIFO + IRQ, RTOS 主输入源 | ✅ 上板通过 |
| `expdemo_wb` | `0xF0010000` | 11 个课程实验硬件多路复用 | ✅ 上板通过 |
| `ir_nec_wb` | `0xF000C000` | 红外 NEC 协议解码 | ✅ 上板通过 |
| `lcd_wb` | `0xF000B000` | HD44780 16×2 LCD (Wishbone) | ✅ 上板通过 |
| `ntt_sdf` | `0xF000F000` | NTT 加速器 (q=3329, N=256) | 🟡 仿真通过, 待上板 |
| `pong_engine` | `0xF0011000` | PONG 硬件引擎, 自含 VGA 时序 (640×480) | 🟡 VHDL+C 完成, 未集成 |
| `conway_engine` | `0xF0012000` | Conway 生命游戏硬件引擎, 双缓冲 | 🟡 VHDL+C 完成, 未集成 |
| `build_info_wb` | `0xF0009000` | 构建信息 ROM (git hash + 时间戳) | ✅ |
| `dds_synth` | `0xF000D000` | DDS 音频合成器 (正弦+FM) | 🟡 仿真 7/7 PASS, 未集成 |

> 地址常量定义于 `src/rtl/lib/de2extra_pkg.vhd`。

## 软件应用

| 应用 | 说明 |
|---|---|
| **de2shell_rtos** (V3 主力) | FreeRTOS 4 任务 (uart_input/shell/active/status), 16 条 CLI 命令, SDRAM 执行 + PS/2 键盘主输入 + VGA 像素 GUI (TWM) |
| **de2shell** (V2 冻结) | 裸机 shell: memtest, crypto, snake, life, dashboard, expdemo, monitor, PS/2。IMEM 64KB，不再更新 |
| **crypto_cli** | 密码学算法库 (AES/SHA/SM4, 源码被多个固件链接复用) |
| **hello** | LED 跑马灯 |
| **sdram_test** | SDRAM 诊断工具 (4096 字密集 + 31 稀疏边界探测) |
| **ps2_test** | PS/2 扫描码测试 |
| **ir_test** | 红外解码测试 |

### de2shell_rtos CLI 命令 (16 条)

| 命令 | 功能 |
|---|---|
| hello | LED 跑马灯 |
| memtest | SDRAM 诊断 |
| crypto | AES/SHA/SM4 CLI |
| ps2 / kbd | PS/2 键盘测试 |
| snake | Snake 全屏 78×27 (CP437 边框 + vblank 同步) |
| info | 系统仪表盘 |
| expdemo | 11 个课程实验 |
| twm | 平铺窗口管理器 (像素模式 GUI) |
| vgadump | VGA framebuffer 诊断 |
| vgam | VGA 模式查询 |
| stats | FreeRTOS 任务列表 + 栈高水位 |
| heapstat | 堆使用统计 |
| cpustat | 各任务 CPU 占用 |

## 目录结构

```
DE2Extra/
├── CLAUDE.md                  # AI agent 协作指南
├── build.sh                   # V2 一键构建 (Git Bash)
├── neorv32/                   # NEORV32 RISC-V CPU (submodule, v1.13.1)
├── src/rtl/
│   ├── de2_115_top.vhd        # de2shell 顶层 (V2 冻结)
│   ├── de2os_top.vhd          # de2os 顶层 (V3 主力, 独立 Quartus 工程)
│   ├── neorv32_wrapper.vhd    # CPU 配置封装
│   ├── bus/wb_intercon.vhd    # Wishbone 互连 (1 主 11 从)
│   ├── periph/                # 外设控制器
│   ├── exp/                   # 课程实验原始/适配模块
│   ├── lib/                   # 公共包 (de2extra_pkg, font_rom_pkg)
│   └── periph/sim/            # 外设仿真测试
├── sw/app/
│   ├── de2shell_rtos/         # V3 主力固件 (FreeRTOS + SDRAM)
│   ├── de2shell/              # V2 冻结固件 (裸机 IMEM)
│   ├── crypto_cli/            # 密码学 CLI
│   └── ...                    # 其他测试应用
├── par/
│   ├── de2extra.qpf/qsf       # V2 de2shell Quartus 工程
│   └── de2os/                 # V3 de2os Quartus 工程
├── constraints/               # 引脚约束 + 时序 (.sdc)
├── tools/                     # 辅助脚本 (gen_font_rom.py 等)
├── run/                       # 部署脚本
└── doc/                       # 设计文档, 验收表, 阶段计划
```

## 构建

### 前置条件

- Quartus Prime 23.1std Lite
- Docker Desktop (RISC-V 交叉编译)
- Git Bash (Windows)

> **重要**: NEORV32 使用 VHDL-2008。首次打开工程须在 Quartus 中设置: Assignments → Settings → VHDL Input → VHDL 2008。

### de2shell_rtos (V3 — 推荐)

Boot mode 0: IMEM 仅存放 ~2KB bootloader，固件通过 UART 上传到 SDRAM 执行。软件更新无需重跑 Quartus。

```bash
# 增量部署 (重编固件 + UART 上传, ~48s)
./run/deploy_de2shell_rtos.sh app

# 仅上传已有 bin (最快)
./run/deploy_de2shell_rtos.sh upload

# 重编 bootloader + Quartus + 烧录 (改 RTL 时)
./run/deploy_de2shell_rtos.sh fpga

# 全量重编 + 烧录 + 上传 (~4min)
./run/deploy_de2shell_rtos.sh full
```

详细部署指南: [`doc/编译烧录前必看.md`](doc/编译烧录前必看.md)

### de2shell (V2 冻结)

```bash
# 一键构建 (固件 + Quartus)
./build.sh app/de2shell

# 烧录
./build.sh --flash app/de2shell
```

## 验收状态

### V2 — de2shell (已冻结)

**v0.1 (V2) 验收完成。** 详见 [验收表](doc/de2shell-module-acceptance.md)。

- 192/213 项 ✅ 通过
- VGA 文字终端上板验证通过 (640×480@60Hz)
- SDRAM 5 项自检全部 PASS
- 11 个课程实验通过 expdemo 多路复用
- AES/SHA/SM4/SM3 + Zk* 硬件加速验证通过
- IR 遥控切频 + 透传验证通过
- LCD 16×2 显示修复验证通过

### V3 — de2shell_rtos (进行中)

V3 主线: FreeRTOS + SDRAM 执行 + PS/2 键盘 + VGA 像素 GUI。

| 阶段 | 内容 | 软件状态 | 上板 |
|---|---|---|---|
| V3P1 | 基础: CP437 256 字符, SDRAM 执行基线 | ✅ 代码完成 | ⬜ 待验证 |
| V3P2 | ExpDemo: 5 个代码缺口修复 | ✅ 代码完成 | ⬜ 待验证 |
| V3P3A | 像素模式 + GUI: TWM, Snake 全屏 | ✅ 代码完成 | ⬜ 待验证 |
| V3P3B | 密码可视化 | 未开始 | — |
| V3P4A | Conway + PONG 硬件引擎 | 🟡 未集成 (QSF/stub/CLI) | — |
| V3P4B | 音频合成 (DDS + FM) | 🟡 仿真通过, 未集成 QSF | — |
| V3P4C | NTT 加速器 | 🟡 未加入 RTOS makefile/CLI | — |
| V3P5 | ChromaShader | 延期 (P4 优先级) | — |

详细进度: [`doc/phases/de2os-rtos-status.md`](doc/phases/de2os-rtos-status.md)

## 许可

本项目代码以 [MIT License](LICENSE) 发布。NEORV32 submodule 保持其原有的 BSD-3-Clause 许可。
