# DE2Extra — NEORV32 RISC-V 全外设终端系统

[English](README.en.md) | 中文

> DE2-115 开发板上的完整 RISC-V 计算机：FreeRTOS 多任务 + VGA 像素 GUI + PS/2 键盘 + 13 个 Wishbone 外设 + 22 条 CLI 命令

## 参考资源

- [NEORV32 RISC-V Processor](https://github.com/stnolting/neorv32) — RISC-V 软核 (submodule, v1.13.1)
- [FreeRTOS](https://www.freertos.org/) — 实时操作系统内核

## 项目概览

```
┌─────────────────────────────────────────────────────┐
│  de2shell_rtos — FreeRTOS 多任务终端 (V3 主力)       │
│  22 条 CLI 命令, 4 任务, SDRAM 执行, PS/2 主输入     │
├─────────────────────────────────────────────────────┤
│       NEORV32 RISC-V 软核 (~4000 LUTs)              │
│       RV32IMC + Zicsr + Zicntr + Zk* 密码扩展        │
├─────────────────────────────────────────────────────┤
│  13 个 Wishbone 从站外设                              │
│  SDRAM | VGA (RGB565) | PS/2 | LCD | IR | NTT |     │
│  ExpDemo | PONG | Conway | Synth | GPU 2D | BuildInfo│
├─────────────────────────────────────────────────────┤
│       DE2-115 FPGA (Cyclone IV E, 114K LEs)          │
└─────────────────────────────────────────────────────┘
```

## 外设地址映射

| 模块 | 地址 | 说明 | 状态 |
|------|------|------|------|
| `sdram_ctrl` | `0x01000000` | 128MB SDRAM, burst, async FIFO CDC | ✅ |
| `vga_text_terminal` | `0xF0000000` | 80×30 文本 + 640×480 RGB565 像素模式 | ✅ |
| `ps2_controller` | `0xF0008000` | PS/2 键盘, RTOS 主输入 | ✅ |
| `lcd_wb` | `0xF000B000` | HD44780 16×2 LCD | ✅ |
| `ntt_sdf` | `0xF000F000` | NTT 加速器 (q=3329, N=256) | 🟡 busy-wait |
| `expdemo_wb` | `0xF0010000` | 13 个课程实验多路复用 | ✅ |
| `pong_engine` | `0xF0011000` | PONG 硬件引擎 | 🟡 待验证 |
| `conway_engine` | `0xF0012000` | Conway 生命游戏引擎 | 🟡 待验证 |
| `synth_engine` | `0xF0013000` | 音频合成 (3xOSC + DX7 FM + WM8731) | 🟡 待验证 |
| `gpu_2d` | `0xF0015000` | 2D GPU, FILL rect burst 写入 | 🟡 待验证 |

## CLI 命令 (22)

hello, memtest, crypto, ps2, snake, life, info, expdemo, twm, conwayhw, ponghw, ntt, synth, pxtest, vgadump, vgam, stats, heapstat, cpustat, clear, monitor, demo

## 目录结构

```
DE2Extra/
├── neorv32/                   # NEORV32 RISC-V CPU (submodule, v1.13.1)
├── src/rtl/                   # VHDL 源码
│   ├── de2os_top.vhd          # V3 顶层 (唯一 Quartus 工程)
│   ├── bus/wb_intercon.vhd    # 1 主 13 从
│   ├── periph/                # 外设控制器
│   └── lib/                   # 公共包
├── sw/
│   ├── lib/                   # 共享库 (HAL, 程序源码, TWM, GFX)
│   ├── app/de2shell_rtos/    # 主固件 (FreeRTOS + SDRAM)
│   └── app/crypto_cli/       # 密码学库 (AES/SHA/SM4)
├── par/de2os/                 # Quartus 工程
├── run/                       # 部署脚本
├── doc/                       # 文档
└── doc/archive/               # 归档文档 (git ignored)
```

## 构建

详细指南: [`doc/编译烧录前必看.md`](doc/编译烧录前必看.md)

> **Bash 环境**: 所有 `bash` / `sh` 脚本必须在 **Git Bash** 中运行（非 WSL 的 `bash.exe`、PowerShell 或 CMD）。请将下方命令中的 `bash` 替换为你本机 Git Bash 的绝对路径，例如 `E:/Software/Scoop/apps/git/current/bin/bash.exe`。

**改了软件（C 代码）**:
```bash
# 编译 (~25s)
docker run --rm -v "E:/Main/JuniorII/NonExam/FPGA/DE2Extra:/work" de2extra-builder bash -c \
  "cd /work && mkdir -p sw/app/de2shell_rtos/build && make -C sw/app/de2shell_rtos all image NEORV32_HOME=/work/neorv32"

# 上传 (~5s, 板子需要在上电 bootloader 状态)
python run/upload_de2os.py COM10 sw/app/de2shell_rtos/neorv32_raw_exe.bin
```

**改了 RTL（VHDL）**: Quartus GUI 打开 `par/de2os/de2os.qpf`, Ctrl+L 编译, Programmer 烧录 `par/de2os/de2os.sof`, 然后再上传固件。

## 验收状态

305/358 项通过 (85%)。详见 [`doc/de2shell-module-acceptance.md`](doc/de2shell-module-acceptance.md)。

V3 里程碑: SDRAM 执行 ✅ | FreeRTOS 4 任务 ✅ | VGA 文本+像素 ✅ | TWM 窗口管理器 ✅ | GPU 2D RTL ✅ | Conway/PONG/NTT/Synth RTL ✅ | 长稳 7h+ 无崩溃 ✅

## 许可

[MIT License](LICENSE)。NEORV32 submodule 保持 BSD-3-Clause。
