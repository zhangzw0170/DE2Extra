<p align="center">
  <img src="doc/promo/banner.svg" alt="DE2Extra Banner" width="100%">
</p>

<h3 align="center">
  DE2Extra：基于 DE2-115 的 RISC-V SoC
</h3>

<p align="center">
  <img src="https://img.shields.io/badge/CPU-NEORV32_RV32IMC-e94560" alt="CPU">
  <img src="https://img.shields.io/badge/FPGA-Cyclone_IV_E-00d4ff" alt="FPGA">
  <img src="https://img.shields.io/badge/RTOS-FreeRTOS_V11.3-f39c12" alt="RTOS">
  <img src="https://img.shields.io/badge/Peripherals-10_Active_Wishbone-66f4a0" alt="Peripherals">
  <img src="https://img.shields.io/badge/License-MIT-66f4a0" alt="License">
</p>

<p align="center">
  <a href="README.en.md">English</a> | 中文
</p>

---

## 项目概览

DE2Extra 是一个基于 [NEORV32](https://github.com/stnolting/neorv32) RISC-V 软核的完整 SoC 系统，运行在 Altera DE2-115 (Cyclone IV E, 114K LEs) FPGA 开发板上。围绕开源 CPU 核心自研了 10 个活跃 Wishbone 外设 IP、SoC 互联、FreeRTOS 固件及 22 个命令行应用。

| | |
|---|---|
| **CPU** | NEORV32 v1.13.1 · RV32IMC + Zicsr + Zicntr + Zbkb/Zbkc/Zbkx/Zknd/Zkne/Zknh/Zksed/Zksh |
| **总线** | Wishbone B4 · 1 主 / 12 从 (10 active, 2 stub) · 32-bit · 组合地址解码 |
| **固件** | FreeRTOS V11.3 · 4 任务 (uart_input/shell/active/status) · ~207KB |
| **启动** | Boot mode 0: 2KB IMEM bootloader → UART 上传 → SDRAM @ `0x01000000` |
| **显示** | VGA 640×480 @60Hz · 80×30 文本模式 + RGB565 像素模式 · GPU 2D FILL |
| **输入** | PS/2 键盘 (主输入) · UART 115200 · IR NEC 红外遥控 |
| **加速** | AES-128 硬件 **107.6×** 加速 · Conway 64×25 硬件引擎 |
| **板级** | SDRAM 128MB · HD44780 LCD 16×2 · 7-SEG ×8 · LED ×24 |

## 系统架构

<p align="center">
  <img src="doc/promo/architecture.svg" alt="系统架构图">
</p>

详见: [交互式架构图](doc/promo/architecture.html) · [演示文稿](doc/promo/slides.html)

## 外设一览

| 外设 | 地址 | 说明 | 上板 |
|------|------|------|:----:|
| `sdram_ctrl` | `0x01000000` | 128MB, burst, async FIFO CDC | ✅ |
| `vga_text_terminal` | `0xF0000000` | 80×30 文本 + 640×480 RGB565 像素 | ✅ |
| `ps2_controller` | `0xF0008000` | PS/2 键盘, scancode + IRQ | ✅ |
| `build_info_wb` | `0xF0009000` | HW/SW 版本 ROM | ✅ |
| `lcd_wb` | `0xF000B000` | HD44780 16×2 LCD | ✅ |
| `ir_nec_wb` | `0xF000C000` | NEC 红外解码 | ✅ |
| `ntt_sdf` | `0xF000F000` | NTT 加速器 (HW 已从综合移除, SW 替代) | ⚠️ |
| `expdemo_wb` | `0xF0010000` | 13 个课程实验硬件多路复用 | ✅ |
| `conway_engine` | `0xF0011000` | Conway 64×25 硬件引擎 | ✅ |
| `synth_engine` | `0xF0012000` | 3×OSC + DX7 FM, WM8731 *(HW 已移除)* | — |
| `gpu_2d` | `0xF0015000` | FILL rect, SDRAM burst 写 | ✅ |

完整板级验证状态: [`doc/phases/de2os-rtos-status.md`](doc/phases/de2os-rtos-status.md)

## CLI 命令 (22 个)

**交互程序** (F1=帮助, F10=退出):

`hello` · `crypto` · `ps2` · `snake` · `conway` · `info` · `riscvasm` · `expdemo` · `twm` · `ntt` · ~~`synth`~~ · `pforth` · `cryptoviz`

**工具命令**:

`selfcheck` · `postverify` · `stats` · `ver` · `clear` · `pxtest` · `vgadump` · `vgamon`

## 目录结构

```
DE2Extra/
├── neorv32/                   # NEORV32 RISC-V CPU (submodule, v1.13.1)
├── src/rtl/                   # VHDL 源码
│   ├── de2os_top.vhd          # 顶层实体 (唯一 Quartus 工程)
│   ├── bus/wb_intercon.vhd    # 1 主 / 12 从地址解码
│   ├── periph/                # 12 个外设控制器 (10 active, 2 removed)
│   └── lib/                   # 公共包 (de2extra_pkg, build_info_pkg 等)
├── sw/
│   ├── lib/                   # 共享库 (HAL, 程序源码, TWM, GFX, pForth)
│   ├── app/de2shell_rtos/    # 主固件 (FreeRTOS + SDRAM)
│   └── app/crypto_cli/       # 密码学库 (AES/SHA/SM4)
├── par/de2os/                 # Quartus 工程
├── run/                       # 部署脚本 (deploy, upload)
└── doc/                       # 文档 + 宣传物料
    └── promo/                 # 架构图, 演示 PPT, 横幅
```

## 构建

详细指南: [`doc/编译烧录前必看.md`](doc/编译烧录前必看.md)

**CLI 工具 (跨平台)**:
```bash
pip install pyserial                                                    # 首次需要
python run/de2extra.py sw-build && python run/de2extra.py sw-upload    # 改软件 (~45s)
python run/de2extra.py hw-build && python run/de2extra.py hw-flash     # 改硬件 (~15min)
```

**旧脚本 (仅 Git Bash)**:
```bash
./run/deploy_de2shell_rtos.sh inc    # 增量: 重编 app + 上传
./run/deploy_de2shell_rtos.sh full   # 全量: app + bootloader + Quartus + 烧录 + 上传
```

**本地仿真** (无需 FPGA):
```bash
cd sw/lib && make run    # SDL2 像素模式 shell, 需 GCC 15+ 和 SDL2
```

## 性能

| 指标 | 数值 |
|------|------|
| 主频 | 50 MHz |
| FPGA 资源 | ~47% (53.5K / 114.5K LEs) |
| AES 硬件加速 | 100+x (vs 纯软件) |
| 固件大小 | ~207KB (SDRAM 执行) |
| 软件增量部署 | ~45s (编译 ~25s + 上传 ~20s) |
| 硬件全量编译 | ~15min (bootloader + Quartus 综合) |
| 长稳测试 | 7h38m 无崩溃 |

## 参考资源

- [NEORV32 RISC-V Processor](https://github.com/stnolting/neorv32) — RISC-V 软核 (v1.13.1 + 本地补丁, BSD-3-Clause)
- [FreeRTOS](https://www.freertos.org/) — 实时操作系统内核 (MIT)
- [Wishbone B4 Specification](https://opencores.org/howto/wishbone) — 片上总线协议
- [DE2-115 User Manual](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=502) — 开发板文档
- [RISC-V Privileged Specification](https://riscv.org/specifications/) — ISA 规范

## NEORV32 本地补丁

子模块锁定在上游 **v1.13.1**，在此基础上有 1 个本地 commit（`72fbfc57`）。改动仅涉及 bootloader，CPU 核心 RTL 未修改。

| 改动 | 文件 | 说明 |
|------|------|------|
| UART 波特率: 19200 → 115200 | `sw/bootloader/config.h` | 匹配板级设置 |
| 自动启动超时: 8s → 1s | `sw/bootloader/config.h` | 加快启动循环 |
| SPI flash: 禁用 | `sw/bootloader/config.h` | DE2-115 未使用 |
| 启动时 SDRAM 自检 | `sw/bootloader/main.c` + `hal/` | 上传前验证 SDRAM |
| KEY0 复位后恢复 SDRAM 固件 | `sw/bootloader/main.c` | 读取 `0x018FFFF0` 标记，免重新下载即可重启上次上传的固件 |
| VGA 镜像 + 上传进度条 | `hal/source/uart.c`, `system.c` | bootloader 输出同步到 VGA，上传时显示进度条 |

## AI 使用声明

本项目在开发过程中使用了 AI 辅助编程。所有 AI 生成的代码均经过审查、上板测试，并按需修改后才纳入最终代码库。

| 类别 | 使用的工具 |
|------|-----------|
| 模型 | GLM 5.1, DeepSeek V4, GPT 5.4 |
| 编程环境 | Claude Code, DeepSeek TUI, Codex |

## 免责声明

本项目仅供学习和研究目的。按照本文档操作涉及 FPGA bitstream 烧录、SDRAM 读写等硬件操作，**请确保你清楚自己在做什么**。因不当操作导致的开发板损坏、数据丢失或其他损失，作者不承担任何责任。

## 许可

本项目代码采用 [MIT License](LICENSE)。

使用的开源组件：

| 组件 | 许可 |
|------|------|
| [NEORV32](https://github.com/stnolting/neorv32) RISC-V Processor (v1.13.1 + 本地补丁) | BSD-3-Clause |
| [FreeRTOS](https://www.freertos.org/) V11.3 Kernel | MIT |
| [RISC-V ISA](https://riscv.org) Specifications | CC-BY-4.0 |
| [Wishbone B4](https://opencores.org/howto/wishbone) Specification | OpenCores License |
