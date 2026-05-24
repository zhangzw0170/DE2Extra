# de2os: FreeRTOS + SDRAM 执行

> 日期: 2026-05-24 | 状态: 固件编译通过，待上板验证
> 前提: SDRAM 稳定 (memtest PASS)，CLINT 已启用

## 与 de2shell 的配置差异

de2shell (裸机) 和 de2os (FreeRTOS) 在同一套 VHDL 代码上通过 **generic 参数切换**，共用同一个 Quartus 工程。切换时只需改 `de2_115_top.vhd` 中 `u_cpu` 的 generic map。

| 项目 | de2shell (裸机) | de2os (FreeRTOS) |
|------|-----------------|-------------------|
| `BOOT_MODE` | 2 (IMEM 直接执行) | 0 (bootloader) |
| `ICACHE_EN` | false | true |
| `ICACHE_BLOCKS` | — | 64 |
| `ICACHE_BLOCK_SZ` | — | 32 |
| `ICACHE_BURSTS` | — | false |
| 代码存放 | IMEM (64KB M9K) | SDRAM (0x01000000) |
| 数据存放 | DMEM (16KB) | DMEM (16KB) |
| 固件格式 | `neorv32_imem_image.vhd` (综合进 FPGA) | `neorv32_exe.bin` (UART 上传) |
| 构建目标 | `make image` | `make exe` |
| 固件更新 | 需要 Quartus 重新综合 | 仅 UART 重传，无需重新综合 |
| 操作系统 | 裸机轮询 (main loop) | FreeRTOS (3 任务抢占调度) |
| UART 波特率 | 115200 (应用) | 19200 (bootloader) → 115200 (应用) |

### de2_115_top.vhd 切换点

**de2shell (当前默认)**:
```vhdl
u_cpu : entity work.neorv32_wrapper
generic map (
    CLOCK_FREQUENCY => 50_000_000,
    IMEM_SIZE       => 64*1024,
    DMEM_SIZE       => 16*1024,
    BOOT_MODE       => 2,
    ICACHE_EN       => false
)
```

**de2os**:
```vhdl
u_cpu : entity work.neorv32_wrapper
generic map (
    CLOCK_FREQUENCY => 50_000_000,
    IMEM_SIZE       => 64*1024,
    DMEM_SIZE       => 16*1024,
    BOOT_MODE       => 0,
    ICACHE_EN       => true,
    ICACHE_BLOCKS   => 64,
    ICACHE_BLOCK_SZ => 32,
    ICACHE_BURSTS   => false
)
```

> 使用 `sw/app/de2os/switch_hw.sh` 自动切换，无需手动编辑 VHDL：
> ```bash
> cd sw/app/de2os
> ./switch_hw.sh de2os    # 切换到 de2os 配置
> ./switch_hw.sh de2shell # 恢复 de2shell 配置
> ./switch_hw.sh status   # 查看当前配置
> ```
> 切换后需 Quartus 重新综合 (Ctrl+L)。

## 部署流程

### 1. 构建

```bash
# Docker 交叉编译固件
./build.sh app/de2os
# 或者仅编译 exe (不触发 Quartus):
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd):/project" de2extra-builder \
    bash -lc "export PATH=/opt/riscv/bin:\$PATH && \
    cd /project/sw/app/de2os && \
    make clean NEORV32_HOME=/project/neorv32 && \
    make exe NEORV32_HOME=/project/neorv32"
```

输出: `sw/app/de2os/neorv32_exe.bin` (6396 bytes, base=0x01000000)

### 2. Quartus 综合

1. `cd sw/app/de2os && ./switch_hw.sh de2os` — 切换到 de2os 配置
2. Quartus → Ctrl+L
3. 生成 `par/de2extra.sof`
4. 测试完成后 `./switch_hw.sh de2shell` — 恢复 de2shell 配置

### 3. 烧录 FPGA

Quartus Programmer → 烧录 `de2extra.sof`

### 4. UART 上传固件

板子启动后进入 NEORV32 bootloader (19200 8N1):

```
NEORV32 Bootloader
...
CMD> _
```

上传 `neorv32_exe.bin`:
- 方式 A: 使用 `make upload UART_TTY=/dev/ttyS10` (需调整波特率)
- 方式 B: 串口工具手动发送 `neorv32_exe.bin` 二进制文件
- 方式 C: 在 bootloader 命令行输入 `u` 进入上传模式，然后发送文件

上传完成后输入 `e` (或自动执行) 开始运行。

## 预期现象

UART 输出 (115200 8N1，上传后自动切换):

```
=== de2os: FreeRTOS on NEORV32 ===
CPU clock: 002FA000 Hz
Starting scheduler...
[gui] started
[crypto] started
[input] started
[gui] tick
[crypto] #00000000 cycles=00002EE0
[gui] tick
[gui] tick
[crypto] #00000001 cycles=00002EE0
[gui] tick
[input] 按键回显...
```

三个任务的预期行为:

| 任务 | 优先级 | 周期 | 输出 |
|------|--------|------|------|
| `t_gui` | 3 (最高) | 每 1 秒 | `[gui] tick` |
| `t_crypto` | 2 | 每 3 秒 | `[crypto] #NNNNNNNN cycles=XXXXXXXX` (1000 次模乘耗时) |
| `t_input` | 1 (最低) | 每 50ms 轮询 | 收到 UART 字符时输出 `[X]` |

板载指示:
- LED: 暂无 (任务 stub 未驱动 GPIO)
- HEX: 暂无
- LCD: 暂无

> 验证要点: 三个任务交错输出，互不阻塞。`t_crypto` 运行时 `t_gui` 仍能按时打印。

## 故障排查

| 现象 | 可能原因 | 解决 |
|------|---------|------|
| bootloader 无输出 | BOOT_MODE 仍是 2 | 确认 generic map |
| bootloader 不接受上传 | UART 波特率不匹配 | bootloader 固定 19200 |
| 上传后无输出 | SDRAM 写入失败 | 先用 de2shell 跑 memtest 确认 SDRAM |
| 只看到第一条输出就死机 | FreeRTOS 栈溢出 | 增大 configMINIMAL_STACK_SIZE |
| 看不到 tick 输出 | CLINT 未启用 | 确认 `IO_CLINT_EN => true` |

## 文件结构

```
sw/app/de2os/
├── makefile                  # SDRAM 链接 + FreeRTOS 源文件
├── FreeRTOSConfig.h          # NEORV32 @ 50MHz, CLINT 地址
├── de2os.ld                  # IRQ 栈符号 (FreeRTOS portASM.S 需要)
├── switch_hw.sh              # 硬件配置切换脚本 (de2os ↔ de2shell)
├── main.c                    # 硬件初始化 + 任务创建 + 平台 hooks
├── t_gui.c / t_gui.h         # GUI 任务 (stub: UART heartbeat)
├── t_crypto.c / t_crypto.h   # Crypto 任务 (stub: 模乘 benchmark)
├── t_input.c / t_input.h     # Input 任务 (stub: UART echo)
└── freertos/                  # git submodule → FreeRTOS/FreeRTOS-Kernel
    ├── tasks.c, queue.c, list.c, ...
    └── portable/GCC/RISC-V/  # RISC-V port (CLINT, MTIME)
```
