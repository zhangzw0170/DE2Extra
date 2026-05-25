# DE2Extra 开发指南

## 项目概述

NEORV32 RISC-V 软核运行在 DE2-115 (Cyclone IV E) FPGA 上。V2 (de2shell) 通过 IMEM 直接执行已冻结。V3 (de2os/de2shell_rtos) 使用 bootloader + UART 上传到 SDRAM 执行，支持 FreeRTOS 多任务。

**V2 -> V3 分水岭**:
- **de2shell**: 裸机终端，IMEM 64KB 直接执行 (boot mode 2)，已冻结不再更新。
- **de2os / de2shell_rtos**: FreeRTOS + SDRAM 执行 + PS/2 键盘 + VGA 像素 GUI。日常开发通过 bootloader 串口上传，不需要重新综合 FPGA。

## 架构总览

```
+-------------------------------------------------------------+
|                     de2os_top.vhd (V3 主用)                   |
|                                                               |
|  +----------+    +---------------+    +----------+            |
|  | neorv32  |---| wb_intercon   |---|sdram_ctrl |---DRAM    |
|  | _wrapper |    |  (地址解码)    |    | (100MHz)  |           |
|  | (50MHz)  |    +---------------+    +----------+            |
|  |          |                                              |
|  | IMEM 64KB|    GPIO -> LED/HEX/LCD                        |
|  | DMEM 16KB|    UART0 -> RS-232 + JTAG bridge              |
|  +----+-----+    PS/2  -> 键盘 (主输入)                      |
|       |                                                     |
|       | 50MHz                                               |
|  +----+--------+                                            |
|  |clk_rst_gen  | PLL: 50MHz (CPU) + 100MHz (SDRAM)           |
|  +-------------+                                            |
+-------------------------------------------------------------+

de2_115_top.vhd (V2 遗留，ExpDemo 板级验证)
```

## 时钟域

| 时钟            | 频率   | 用途                              |
|-----------------|--------|-----------------------------------|
| clk_50m         | 50MHz  | CPU、UART、GPIO、Wishbone          |
| clk_sdram       | 100MHz | SDRAM 控制器内部逻辑               |
| clk_sdram_shift | 100MHz | DRAM_CLK 引脚 (当前稳定值 `+1.56ns` 相移) |

## 地址映射

常量定义在 `src/rtl/lib/de2extra_pkg.vhd`。

| 范围            | 用途         | 说明                             |
|-----------------|--------------|----------------------------------|
| 0x00000000      | IMEM         | 64KB 指令存储 (bootloader 固化在此) |
| 0x80000000      | DMEM         | 16KB 数据存储                    |
| 0x01000000      | SDRAM        | 128MB (XBUS -> wb_intercon)     |
| 0xF0000000      | VGA 终端     | 32KB (text buffer + 像素模式)     |
| 0xF0008000      | PS/2 键盘    | 4KB (扫描码 FIFO + IRQ)          |
| 0xF0009000      | 系统定时器   | 4KB, timer_wb                    |
| 0xF000A000      | 中断控制器   | 4KB, intc_wb                     |
| 0xF000B000      | LCD 控制器   | 4KB, HD44780 (lcd_wb)            |
| 0xF000C000      | IR 接收器    | 4KB (ir_nec_wb)                  |
| 0xF000D000      | DDS 音频     | 4KB, 预留                        |
| 0xF000E000      | SD 卡 SPI    | 4KB, 预留                        |
| 0xF000F000      | NTT 加速器   | 4KB, 编译通过待上板 (V3)          |
| 0xF0010000      | ExpDemo      | 4KB (实验多路复用)                |
| 0xF0011000      | Pong 引擎    | 4KB (硬件 Pong)                   |
| 0xF0012000      | Conway 引擎  | 4KB (硬件生命游戏)                |

## 开发环境

| 工具                    | 版本/路径                                       |
|------------------------|------------------------------------------------|
| Quartus Prime          | 23.1std Lite (`/e/Software/intelFPGA_lite/23.1std/`) |
| Docker                 | `de2extra-builder` 镜像 (RISC-V 交叉编译)       |
| Shell                  | **Git Bash on Windows** (不要用 PowerShell)       |
| 串口                    | COM10, 115200 8N1                               |
| 终端                    | Quartus 内置 Console 或外部终端                    |

Phase 1 的完整上板排障过程见 `archive/v2phase/phase1-sdram-debug-report.md`。

## 引导流程

### Boot Mode 0: Bootloader + UART 上传 (V3 主用)

1. FPGA 上电 / 按 KEY0 复位后，NEORV32 执行 IMEM 中的 bootloader
2. Bootloader 等待 UART 接收固件 (`neorv32_exe.bin`)
3. 固件通过 UART 115200 上传到 SDRAM 地址 `0x01000000`
4. 上传完成后 bootloader 跳转到 SDRAM 执行

这意味着 **改软件代码不再需要重新综合 FPGA**，只需重新编译 app 并串口上传。

### Boot Mode 2: IMEM 直接执行 (V2 de2shell)

de2shell 仍使用此模式，固件直接固化到 IMEM 的 M9K block RAM 中。已冻结，仅保留兼容。

## 构建与部署

### 重要: 必须使用 Git Bash

Windows 上 PowerShell 中的 `bash` 命令会落到 WSL，导致报错:

```
execvpe(/bin/bash) failed: No such file or directory
```

正确做法是从 Git Bash 运行，或在 PowerShell 中显式调用:

```powershell
& 'E:\Software\Scoop\apps\git\current\bin\bash.exe' run/deploy_de2shell_rtos.sh app
```

### 增量部署 (bootloader-first 流程)

日常开发中 90% 的情况只需要 `app` 档。完整指南见 `doc/编译烧录前必看.md`。

#### de2shell_rtos 部署命令

```bash
# 第 1 档: 仅上传 (bin 已编好，不想重新编译)
./run/deploy_de2shell_rtos.sh upload

# 第 2 档: 编译 app + 上传 (最常用)
./run/deploy_de2shell_rtos.sh app

# 第 3 档: 仅重烧 .sof (不重新上传 app)
./run/deploy_de2shell_rtos.sh fpga

# 第 4 档: 全量重编 (仅在 RTL 变更时)
./run/deploy_de2shell_rtos.sh full    # 编译 app + Quartus + 烧录 + 上传
```

兼容旧命令: `all` 等价于 `full`，`flash` 等价于 `fpga` + `upload`，`inc` 等价于 `app`。

#### deploy_de2shell_rtos.sh 执行过程

```
[app 档] (日常软件迭代):
  1/2  Docker 交叉编译 -> sw/app/<name>/neorv32_exe.bin
  2/2  等待 bootloader (按 KEY0) -> UART 上传到 0x01000000

[full 档] (RTL 变更时):
  1/4  Docker 交叉编译
  2/4  gen_hw_build_info.py (生成版本信息)
  3/4  Quartus 综合 (~2-3min) -> par/de2os/de2os.sof
  4/4  JTAG 烧录 + UART 上传
```

实测耗时 (2026-05-25): full 档总计约 4 分钟 (app 编译 25s + bootloader 17s + Quartus 152s + 烧录 12s + 上传 23s)。

### 什么时候需要重综合 (full / fpga)

| 改了什么                                  | 需要重编                    |
|------------------------------------------|-----------------------------|
| C 代码 (sw/app/*/main.c 等)              | `app` (编译 + 上传)        |
| FreeRTOS 任务 / CLI / GUI 软件            | `app` (编译 + 上传)        |
| VHDL 逻辑 (src/rtl/**)                   | `full` (综合 + 烧录 + 上传) |
| 引脚 / QSF (par/de2os/*.qsf)             | `full`                      |
| PLL / 时钟 (src/ip/altpll_50_100.vhd)    | `full`                      |
| Bootloader / IMEM / DMEM 配置             | `full`                      |
| 总线地址映射 (wb_intercon.vhd)           | `full`                      |

### V2 全量构建 (build.sh, 仅 de2shell)

de2shell (V2) 仍可使用旧的全量构建脚本:

```bash
# Git Bash 中运行
MSYS_NO_PATHCONV=1 bash build.sh --flash app/sdram_test
```

```
[1/3] 固件编译 (Docker): main.c -> main.elf -> neorv32_imem_image.vhd
[2/3] 复制 IMEM image 到 src/rtl/
[3/3] Quartus 编译 -> par/de2extra.sof -> JTAG 烧录
```

### 不用脚本手动操作

**V3 (de2os/de2shell_rtos)**:
1. 固件: `cd sw/app/<name>/ && make clean exe NEORV32_HOME=../../../neorv32`
2. 上传: `python run/upload_de2os.py COM10 sw/app/<name>/neorv32_exe.bin --wait`
3. 重综合: 打开 `par/de2os/de2os.qpf`，Ctrl+L 编译
4. 烧录: Tools -> Programmer -> 选择 `par/de2os/de2os.sof` -> Start

**V2 (de2shell)**:
1. 固件: `cd sw/app/<name>/ && make clean all image NEORV32_HOME=../../../neorv32`
2. 复制: `cp neorv32/rtl/core/neorv32_imem_image.vhd src/rtl/`
3. Quartus: 打开 `par/de2extra.qpf`，Ctrl+L 编译
4. 烧录: Tools -> Programmer -> 选择 `par/de2extra.sof` -> Start

## 串口调试

```powershell
# 启动串口监控 (PowerShell)
.\tools\serial\start_serial_monitor.ps1
```

- 默认日志: `logs/serial-com10.log`
- 参数: `COM10`, `115200 8N1`

按 KEY0 后串口会显示 bootloader 提示符，等待上传。

## 新增应用

在 `sw/app/` 下创建目录，模板:

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
3. 在 `de2os_top.vhd` (V3) 或 `de2_115_top.vhd` (V2) 实例化
4. 在 `par/de2os/*.qsf` (V3) 或 `par/de2extra.qsf` (V2) 分配引脚 (优先查仓库内 `DE2-115_pin_table_backup.md`，原始来源是 `FPGA/DE2-115引脚表.xlsx`)
5. 在 `src/rtl/lib/de2extra_pkg.vhd` 添加地址常量
6. 软件通过基地址指针访问

## 调试手段

| 方法              | 用途                                       |
|------------------|---------------------------------------------|
| GPIO -> LED/HEX/LCD | 快速显示状态，不需要串口                    |
| UART0 -> RS-232   | `neorv32_uart0_printf` 详细日志              |
| JTAG UART         | 通过 Quartus JTAG 在 PC 上查看 (需要 uart_jtag_bridge) |
| SignalTap         | Quartus 内嵌逻辑分析仪，抓内部信号时序      |

## 关键文件索引

### 顶层

```
src/rtl/de2os_top.vhd        -- 板级顶层 (V3, de2os/de2shell_rtos, 主用)
src/rtl/de2_115_top.vhd      -- 板级顶层 (V2, de2shell, 已冻结)
src/rtl/neorv32_wrapper.vhd  -- CPU 封装，55 个 generic 配置
```

### 时钟与总线

```
src/rtl/glue/clk_rst_gen.vhd -- PLL + 复位生成
src/rtl/bus/wb_intercon.vhd  -- Wishbone 总线互连，地址解码 (s0-s8)
src/rtl/lib/de2extra_pkg.vhd  -- 公共常量/函数 (地址映射等)
```

### 外设

```
src/rtl/periph/sdram_ctrl.vhd          -- SDRAM 控制器 (100MHz 状态机)
src/rtl/periph/vga_text_terminal.vhd   -- VGA 80x25 文字终端 + 像素模式
src/rtl/periph/vga_pixel_ctrl.vhd      -- VGA 像素控制器 (SDRAM framebuffer)
src/rtl/periph/ps2_controller.vhd      -- PS/2 键盘控制器 + IRQ
src/rtl/periph/ir_nec_wb.vhd           -- IR NEC 解码 (Wishbone)
src/rtl/periph/lcd_wb.vhd              -- LCD HD44780 (Wishbone)
src/rtl/periph/timer_wb.vhd            -- 系统定时器
src/rtl/periph/intc_wb.vhd             -- 中断控制器
src/rtl/periph/ntt_sdf.vhd             -- NTT 加速器 (编译通过待上板)
src/rtl/periph/expdemo_top.vhd         -- 实验多路复用 (V2 板级验证)
src/rtl/periph/pong_engine.vhd         -- 硬件 Pong 引擎
src/rtl/periph/conway_engine.vhd       -- 硬件生命游戏引擎
src/rtl/periph/async_fifo.vhd          -- 异步 FIFO (SDRAM CDC)
src/rtl/periph/build_info_wb.vhd       -- 构建信息寄存器
```

### IP 与 Quartus 工程

```
src/ip/altpll_50_100.vhd     -- PLL wrapper (50MHz + 100MHz + 相移)
par/de2os/de2os.qsf          -- Quartus 工程设置 (V3, 主用)
par/de2os/de2os.sof          -- FPGA 比特流 (V3)
par/de2extra.qsf             -- Quartus 工程设置 (V2, 已冻结)
par/de2extra.sof             -- FPGA 比特流 (V2)
```

### 软件应用

```
sw/app/de2shell_rtos/        -- V3 主力固件: FreeRTOS + SDRAM + PS/2 + VGA
sw/app/de2os/                -- V3 legacy FreeRTOS 测试
sw/app/de2shell/             -- V2 裸机终端 (已冻结)
sw/app/crypto_cli/           -- 独立 AES/SHA/SM4 CLI
sw/app/sdram_test/           -- SDRAM 诊断程序
sw/app/hello/                -- Hello World
sw/app/game_snake/           -- 独立贪吃蛇
sw/app/game_life/            -- 独立生命游戏
sw/app/ps2_test/             -- PS/2 扫描码测试
sw/app/ir_test/              -- IR NEC 解码测试
```

### 部署脚本

```
run/deploy_de2shell_rtos.sh      -- V3 增量部署 (boot mode 0, app/upload/fpga/full)
run/deploy_de2shell_rtos_imem.sh -- V3 IMEM 直接烧录 (boot mode 2, 调试用)
run/upload_de2os.py              -- UART 上传工具
run/gen_hw_build_info.py         -- 生成构建版本信息
build.sh                         -- V2 全量构建 (de2shell, IMEM 固化)
```

## 注意事项

- **引脚表是唯一真理**: 优先使用仓库内 `DE2-115_pin_table_backup.md` / `DE2-115_pin_table_backup.csv`，原始来源是 `FPGA/DE2-115引脚表.xlsx`；绝不能猜引脚
- **IMEM 大小**: 64KB，bootloader 占用 IMEM，app 运行在 SDRAM
- **DMEM 大小**: 16KB，大数据放 SDRAM
- **XBUS 超时**: 2048 周期 (~41us @50MHz)，SDRAM 访问要远快于这个
- **SDRAM 初始化**: 上电后 ~200us，软件中 `sdram_wait_init()` 等待更久以确保
- **DRAM_CLK 相移**: 当前稳定值为 `1560ps`，通过 `sdram_test` 的实测结果
- **ICACHE burst**: de2os 启用了 ICACHE burst (`cti=010`) + async FIFO CDC，单次访问路径不变
- **KEY0 不会自动下载新固件**: 只复位到 bootloader，需要运行 `upload` 或 `app` 才能下发新 bin
- **bootloader 不清 VGA**: 按 KEY0 后 VGA 画面残留是正常的，不代表复位失败
