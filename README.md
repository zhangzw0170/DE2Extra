# DE2Extra — NEORV32 RISC-V 全外设终端系统

[English](README.en.md) | 中文

> 让 DE2-115 开发板变成一台完整的计算机：RISC-V CPU + VGA 终端 + PS/2 键盘 + SDRAM + 密码学加速 + 课程实验多路复用

## AI 使用声明

本项目在开发过程中使用了以下大语言模型辅助：[DeepSeek V4](https://chat.deepseek.com/)、[GLM 5.1](https://chatglm.cn/)、[GPT 5.4](https://chat.openai.com/)。所有 AI 生成内容均经过人工审查。

## 参考资源

- [NEORV32 RISC-V Processor](https://github.com/stnolting/neorv32) — 本项目使用的 RISC-V 软核
- [FreeRTOS](https://www.freertos.org/) — de2os 使用的实时操作系统内核
- [DE2-115 System CD](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=167&No=506) — Terasic 官方例程与参考资料

## 项目概览

在 DE2-115 (Cyclone IV E) 上运行 [NEORV32](https://github.com/stnolting/neorv32) RISC-V 软核，通过自定义 Wishbone 外设驱动板载硬件，运行裸机 C 固件实现多频道终端系统。

```
┌──────────────────────────────────────────────────┐
│  de2shell — 多频道终端 (裸机 C)                   │
│  help / memtest / crypto / snake / life / dash   │
│  expdemo (11 个课程实验) / monitor / ps2 / ...   │
├──────────────────────────────────────────────────┤
│     NEORV32 RISC-V 软核 (~4000 LUTs)             │
│     RV32IMC + Zicsr + Zicntr + Zk* 密码扩展      │
├──────────────────────────────────────────────────┤
│  自定义 VHDL 外设 (通用寄存器接口, 平台无关)       │
│  VGA | PS/2 | LCD | IR | ExpDemo | ...           │
├──────────────────────────────────────────────────┤
│     DE2-115 FPGA (Cyclone IV E, 114K LEs)        │
└──────────────────────────────────────────────────┘
```

## 硬件平台

**主平台**: Terasic DE2-115 (`EP4CE115F29C7`)

- **FPGA**: Cyclone IV E, 114,480 LEs, 266 硬件乘法器, 4 PLL
- **存储**: 128MB SDRAM, 2MB SRAM, 8MB Flash, SD 卡槽
- **显示**: 16×2 LCD, 8 个七段数码管, 27 个 LED (9G+18R), VGA (8-bit/通道 DAC, RGB565)
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

所有自定义外设使用通用寄存器接口设计，不绑定特定总线，换板只需改适配层。

| 模块 | 地址 | 说明 | 状态 |
|---|---|---|---|
| `sdram_ctrl` | `0x01000000` | 128MB SDRAM 控制器, 支持 burst | ✅ 上板通过 |
| `vga_text_terminal` | `0xF0000000` | 80×25 彩色文字终端, 640×480@60Hz, RGB565 | ✅ 上板通过 |
| `ps2_controller` | `0xF0002000` | PS/2 键盘 + FIFO + 中断 | ✅ 上板通过 |
| `ir_nec_wb` | `0xF0009000` | 红外 NEC 协议解码 | ✅ 上板通过 |
| `lcd_wb` | `0xF0008000` | HD44780 16×2 LCD (Wishbone) | ✅ 上板通过 |
| `expdemo_wb` | `0xF000D000` | 11 个课程实验硬件多路复用 | ✅ 上板通过 |
| `timer_wb` | `0xF0004000` | 系统定时器 (IR 脉宽捕获) | ✅ |
| `intc_wb` | `0xF0006000` | 中断控制器 (IR/Timer/PS2) | ✅ |

> **V3 规划**: NTT 加速器、VGA 像素模式控制器、WM8731 音频、SD 卡 SPI。详见 [`doc/phases/phase5-sdram-gui.md`](doc/phases/phase5-sdram-gui.md)。

## 软件应用

| 应用 | 说明 |
|---|---|
| **de2shell** | 主固件: 命令行 shell, memtest, crypto (AES/SHA/SM4+Zk*加速), snake, life, dashboard, expdemo, monitor, PS/2 |
| **de2os** | 实验性: FreeRTOS + SDRAM 执行 + ICACHE burst |
| **crypto_cli** | 密码学算法库 (源码被 de2shell 链接复用) |
| **hello** | LED 跑马灯 + VGA 显示 |
| **sdram_test** | SDRAM 诊断工具 (5 项测试 + LCD 协议) |
| **ps2_test** | PS/2 扫描码测试 |
| **ir_test** | 红外解码测试 |

## 目录结构

```
DE2Extra/
├── CLAUDE.md                  # AI agent 协作指南
├── build.sh                   # 一键构建 (Git Bash)
├── neorv32/                   # NEORV32 RISC-V CPU (submodule)
├── src/rtl/
│   ├── de2_115_top.vhd        # de2shell 顶层实体
│   ├── de2os_top.vhd          # de2os 顶层实体 (独立工程)
│   ├── neorv32_wrapper.vhd    # CPU 配置封装
│   ├── bus/wb_intercon.vhd    # Wishbone 互连
│   ├── periph/                # 外设控制器
│   ├── exp/                   # 课程实验原始/适配模块
│   └── lib/                   # 公共包 (de2extra_pkg)
├── sw/app/
│   ├── de2shell/              # 主固件 (裸机多频道终端)
│   ├── de2os/                 # FreeRTOS 固件
│   ├── crypto_cli/            # 密码学 CLI
│   └── ...                    # 其他测试应用
├── par/
│   ├── de2extra.qpf/qsf       # de2shell Quartus 工程
│   └── de2os/                 # de2os 独立 Quartus 工程
├── constraints/               # 引脚约束 + 时序 (.sdc)
├── run/                       # 部署脚本
└── doc/                       # 设计文档, 验收表, 阶段计划
```

## 构建

### 前置条件

- Quartus Prime 23.1std Lite
- Docker Desktop (RISC-V 交叉编译)
- Git Bash (Windows)

### de2shell

```bash
# 一键构建 (固件 + Quartus)
./build.sh app/de2shell

# 烧录
./build.sh --flash app/de2shell
```

或手动分步:

```bash
# 1. 固件编译
docker run --rm -v "$(pwd):/project" de2extra-builder bash -lc \
  'export PATH=/opt/riscv/bin:$PATH; cd /project/sw/app/de2shell && make clean NEORV32_HOME=/project/neorv32 && mkdir -p build && make image NEORV32_HOME=/project/neorv32'

# 2. 复制 IMEM 镜像
cp sw/app/de2shell/neorv32_imem_image.vhd src/rtl/

# 3. Quartus 编译 (GUI: Ctrl+L 或 CLI)
quartus_sh --flow compile par/de2extra -c de2extra
```

> **重要**: NEORV32 使用 VHDL-2008。首次打开工程须在 Quartus 中设置: Assignments → Settings → VHDL Input → VHDL 2008。

### de2os (实验)

```bash
cd par/de2os && quartus_sh --flow compile de2os
```

## V2 验收状态

**v0.1 (V2) 验收完成。** 详见 [验收表](doc/de2shell-module-acceptance.md)。

- 192/213 项 ✅ 通过
- VGA 文字终端上板验证通过 (640×480@60Hz)
- SDRAM 5 项自检全部 PASS
- 11 个课程实验通过 expdemo 多路复用
- AES/SHA/SM4/SM3 + Zk* 硬件加速验证通过
- IR 遥控切频 + 透传验证通过
- LCD 16×2 显示修复验证通过

移至 V3: NTT 硬件加速、VGA 像素模式 (Win 3.0 GUI)、Exp6/7 画廊、snake Game Over 显示、音频子系统。

## 许可

本项目代码以 [MIT License](LICENSE) 发布。NEORV32 submodule 保持其原有的 BSD-3-Clause 许可。
