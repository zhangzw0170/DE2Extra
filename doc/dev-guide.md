# DE2Extra 开发指南

## 项目概述

NEORV32 RISC-V 软核运行在 DE2-115 (Cyclone IV E) FPGA 上。CPU 执行存在片 IMEM 中的固件，通过 XBUS 总线访问 SDRAM 和外设。

## 架构总览

```
┌─────────────────────────────────────────────────────┐
│                    de2_115_top.vhd                    │
│                                                      │
│  ┌──────────┐    ┌──────────────┐    ┌───────────┐   │
│  │ neorv32   │───│ wb_intercon  │───│sdram_ctrl │──DRAM│
│  │ _wrapper  │    │  (地址解码)   │    │ (100MHz)   │   │
│  │  (50MHz)  │    └──────────────┘    └───────────┘   │
│  │           │                                          │
│  │  IMEM     │    GPIO → LED/HEX/LCD                  │
│  │  (64KB)   │    UART0 → RS-232 + JTAG bridge        │
│  │  DMEM     │                                          │
│  │  (16KB)   │                                          │
│  └─────┬─────┘                                          │
│        │ 50MHz                                          │
│  ┌─────┴──────┐                                          │
│  │clk_rst_gen │ PLL: 50MHz (CPU) + 100MHz (SDRAM)       │
│  └────────────┘                                          │
└─────────────────────────────────────────────────────┘
```

## 时钟域

| 时钟   | 频率  | 用途                     |
|--------|-------|--------------------------|
| clk_50m | 50MHz | CPU、UART、GPIO、Wishbone |
| clk_sdram | 100MHz | SDRAM 控制器内部逻辑   |
| clk_sdram_shift | 100MHz | DRAM_CLK 引脚（当前稳定值 `+1.56ns` 相移） |

## 地址映射

| 范围            | 用途         | 说明                    |
|-----------------|--------------|-------------------------|
| 0x00000000      | IMEM         | 64KB 指令存储            |
| 0x80000000      | DMEM         | 16KB 数据存储            |
| 0x01000000      | SDRAM        | 128MB (XBUS → wb_intercon) |
| 0xF0000000      | VGA 终端     | 8KB (text buffer + 控制寄存器) |
| 0xF0002000      | PS/2 键盘    | 4KB (扫描码 FIFO + IRQ)  |
| 0xF0004000      | 系统定时器   | 4KB，预留                |
| 0xF0006000      | 中断控制器   | 4KB，预留                |
| 0xF0008000      | LCD 控制器   | 4KB，已实现 (lcd_wb)     |
| 0xF0009000      | IR 接收器    | 4KB，已实现 (ir_nec_wb)  |
| 0xF000A000      | DDS 音频     | 4KB，预留                |
| 0xF000B000      | SD 卡 SPI    | 4KB，预留                |
| 0xF000C000      | NTT 加速器   | 4KB，硬件禁用, C 驱动完成 |
| 0xF000D000      | ExpDemo      | 4KB (实验多路复用)       |

## 开发环境

| 工具                    | 版本/路径                                       |
|------------------------|------------------------------------------------|
| Quartus Prime          | 23.1std Lite (`/e/Software/intelFPGA_lite/23.1std/`) |
| Docker                 | `de2extra-builder` 镜像 (RISC-V 交叉编译)       |
| Shell                  | Git Bash on Windows                             |
| 终端                    | Quartus 内置 Console 或外部终端                    |

Phase 1 的完整上板排障过程见 `phases/phase1-sdram-debug-report.md`。

## 一键构建

```bash
# 在 Git Bash 中运行 (项目根目录)
MSYS_NO_PATHCONV=1 bash build.sh --flash app/sdram_test
```

### build.sh 三个阶段

```
[1/3] 固件编译 (Docker)
      sw/app/<app>/main.c → main.elf → neorv32_imem_image.vhd

[2/3] Quartus 编译 (~2-3min)
      全量综合 + 布局布线 + 时序分析 → par/de2extra.sof

[3/3] 烧录 (可选 --flash)
      quartus_pgm 通过 USB-Blaster JTAG → FPGA
```

### 常用命令

```bash
bash build.sh app/sdram_test          # 只编译
bash build.sh app/hello              # 编译 hello 固件
bash build.sh --flash app/sdram_test  # 编译 + 烧录
```

### 不用脚本手动操作

1. 固件编译: 进入 `sw/app/<name>/`，运行 `make clean all image NEORV32_HOME=../../../neorv32`
2. 复制: `cp neorv32/rtl/core/neorv32_imem_image.vhd src/rtl/`
3. Quartus: 打开 `par/de2extra.qpf`，Ctrl+L 编译
4. 烧录: Tools → Programmer → 选择 `par/de2extra.sof` → Start

## 修改代码后需要重编什么

| 改了什么                        | 需要重编           | 耗时   |
|-------------------------------|--------------------|----|
| C 代码 (sw/app/*/main.c)       | 固件 → IMEM → Quartus | ~3min |
| VHDL 逻辑 (src/rtl/**)        | 只跑 Quartus        | ~2min |
| 引脚/QSF (par/de2extra.qsf)    | 只跑 Quartus        | ~2min |
| PLL (src/ip/altpll_50_100.vhd) | 只跑 Quartus        | ~2min |

## 新增应用

在 `sw/app/` 下创建目录，模板：

```makefile
include ../../neorv32/common.mk
```

```c
#include <neorv32.h>

int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(115200, 0);
    neorv32_gpio_dir_set(0xFFFFFFFF);
    // ...
    while (1) {}
    return 0;
}
```

## 新增外设

1. 在 `src/rtl/periph/` 写 VHDL 模块
2. 在 `wb_intercon.vhd` 添加 slave 端口 + 地址解码 `cs`
3. 在 `de2_115_top.vhd` 实例化，连接顶层信号
4. 在 `par/de2extra.qsf` 分配引脚（优先查仓库内 `DE2-115_pin_table_backup.md`，原始来源是 `FPGA/DE2-115引脚表.xlsx`）
5. 软件通过对应基地址访问，例如 `#define VGA_BASE ((volatile uint32_t *)0xF0000000u)`

## 调试手段

| 方法        | 用途                                       |
|------------|---------------------------------------------|
| GPIO → LED/HEX/LCD | 快速显示状态，不需要串口                    |
| UART0 → RS-232   | `neorv32_uart0_printf` 详细日志              |
| JTAG UART         | 通过 Quartus JTAG 在 PC 上查看（需要 uart_jtag_bridge） |
| SignalTap         | Quartus 内嵌逻辑分析仪，抓内部信号时序      |

当前常用串口观察方式:

```powershell
.\tools\serial\start_serial_monitor.ps1
```

- 默认日志: `logs/serial-com10.log`
- 当前实板参数: `COM10`, `115200 8N1`

## 关键文件索引

```
src/rtl/de2_115_top.vhd      — 板级顶层 (de2shell)
src/rtl/de2os_top.vhd        — 板级顶层 (de2os, FreeRTOS)
src/rtl/neorv32_wrapper.vhd  — CPU 封装，55 个 generic 配置
src/rtl/glue/clk_rst_gen.vhd — PLL + 复位生成
src/rtl/bus/wb_intercon.vhd  — Wishbone 总线互连，地址解码 (s0-s8)
src/rtl/periph/sdram_ctrl.vhd— SDRAM 控制器 (100MHz 状态机)
src/rtl/periph/vga_text_terminal.vhd — VGA 80×25 文字终端
src/rtl/periph/ps2_controller.vhd   — PS/2 键盘控制器 + IRQ
src/rtl/periph/ir_nec_wb.vhd       — IR NEC 解码 (Wishbone)
src/rtl/periph/lcd_wb.vhd          — LCD HD44780 (Wishbone)
src/rtl/periph/ntt_sdf.vhd         — NTT 加速器 (禁用)
src/rtl/periph/expdemo_top.vhd     — 实验多路复用
src/rtl/lib/de2extra_pkg.vhd  — 公共常量/函数
src/ip/altpll_50_100.vhd     — PLL wrapper (50MHz + 100MHz + 相移)
par/de2extra.qsf             — Quartus 工程设置、引脚分配
par/de2extra.sof             — FPGA 比特流 (de2shell)
par/de2os/de2os.sof          — FPGA 比特流 (de2os)
sw/app/de2shell/             — 主固件 (裸机终端)
sw/app/de2os/                — FreeRTOS 固件 (实验)
sw/app/sdram_test/main.c     — SDRAM 自测程序
sw/app/hello/main.c          — Hello World
```

## 注意事项

- **引脚表是唯一真理**: 优先使用仓库内 [DE2-115_pin_table_backup.md](DE2-115_pin_table_backup.md) / [DE2-115_pin_table_backup.csv](DE2-115_pin_table_backup.csv)，其原始来源是仓库外 `FPGA/DE2-115引脚表.xlsx`；绝不能猜引脚
- **IMEM 大小**: 64KB，固件不能超过这个限制（de2shell 当前 ~39KB，超过旧 32KB 配置）
- **DMEM 大小**: 16KB，大数据放 SDRAM
- **XBUS 超时**: 2048 周期 (~41us @50MHz)，SDRAM 访问要远快于这个
- **SDRAM 初始化**: 上电后 ~200us，软件中 `sdram_wait_init()` 等待更久以确保
- **DRAM_CLK 相移**: 当前稳定值为 `1560ps`，这是本板现阶段通过 `sdram_test` 的实测结果
