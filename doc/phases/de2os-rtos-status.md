# de2os FreeRTOS 集成状态

> 日期: 2026-05-26
> 状态: 软件侧已收敛到可构建基线，待 Quartus 复编译和上板验证
> 硬件工程: `par/de2os/` (top entity: `de2os_top`)
> 目标固件: `sw/app/de2shell_rtos/`

## 当前结论

`de2os` 这条线当前已经不再受 `IMEM 64KB` 约束。`sw/app/de2shell_rtos/` 的 `.text/.rodata` 运行在 SDRAM `0x01000000`，最新构建产物为：

- `Executable (EXE): 73500 bytes @ 0x01000000`
- `.text = 73424`
- `.data = 76`
- `.bss = 32640`

其中 `.bss` 大不是因为 DMEM 爆了，而是因为 FreeRTOS heap 已经迁到 SDRAM：

- `.freertos_heap` at `0x01900000`, size `0x4000`
- `ucHeap` at `0x01900000`
- `__de2_framebuffer_base = 0x01800000`

因此当前主瓶颈已经从“代码放不下”转成：

1. 共享 RTL 改动是否都能在 `par/de2os/` 下重新通过 Quartus。
2. 板上运行时，ICACHE burst + SDRAM + VGA 像素模式这条链是否稳定。

## 已完成

### 1. SDRAM 执行基线已建立

- `de2os` 使用 bootloader 上传固件到 SDRAM，再从 `0x01000000` 执行。
- 这条路线已经绕开裸机 `de2shell` 的 `IMEM 64KB` 上限。
- `sw/app/de2shell_rtos/makefile` 已将 `__neorv32_rom_size` 提到 `128M`。

### 2. FreeRTOS heap 已移出 16KB DMEM

FreeRTOS 内核通过 NEORV32 上游集成的 RISC-V port 提供（`neorv32/sw/ext/`），FreeRTOS+CLI 作为本地源文件集成在 `sw/app/de2shell_rtos/FreeRTOS_CLI.c` / `FreeRTOS_CLI.h`，不使用子模块。

原先的运行时炸弹是 `configTOTAL_HEAP_SIZE` 只能缩到 2KB 才能链接，但 4 个任务 + 队列运行时一定不够。

当前修复：

- `configAPPLICATION_ALLOCATED_HEAP = 1`
- `configTOTAL_HEAP_SIZE = 16384`
- 新增 `sw/app/de2shell_rtos/rtos_memory.c`
- 链接脚本新增 `.freertos_heap` 段，放到 `0x01900000`

结果：

- FreeRTOS 任务/队列的动态分配不再挤占 DMEM
- `de2os` 当前的内存约束重点变回全局变量、RTOS 内核小对象和主数据段，而不是 `ucHeap[]`

### 3. framebuffer 已与代码区分离

原先 `fb_hal.c` 使用 `0x01000000` 作为 framebuffer 基址，这与 SDRAM 代码入口重叠，Win30 写像素时会覆盖程序自身。

当前修复：

- framebuffer 移到 `0x01800000`
- FreeRTOS heap 放在 `0x01900000`

这至少消除了“GUI 一启动就自毁代码段”的硬冲突。

### 4. VGA 像素模式已接通软件控制

旧状态里 `vga_pixel_mode <= '0'` 是硬编码，Win30 即使初始化 framebuffer 也无法真正切到像素模式。

当前已改为：

- `vga_text_terminal` 和 `vga_pixel_ctrl` 共享同一 VGA Wishbone 窗口
- 文本控制寄存器移到 `0x1F40..0x1F54`
- 像素控制寄存器使用 `0x1F80..`
- `mode_en_o => vga_pixel_mode`
- 顶层 VGA 输出由 `vga_pixel_mode` 选择 text/pixel

软件侧对应改动：

- `sw/app/de2shell/fb_hal.c` 写 `0xF0000000 + 0x1F80/0x1F84`
- `fb_shutdown()` 会关闭像素模式

### 5. PS/2 已接入 RTOS 输入队列（主输入源）

当前 `t_uart_input()` 已同时轮询：

- UART 输入
- PS/2 MMIO (`0xF0008000`)，优先级与 UART 相同

并将可解码为 ASCII 的按键送入 `xInputQueue`。PS/2 键盘现在是主要输入方式（板上无 UART 终端时唯一输入源）。

这意味着：

- shell 不再是纯 UART 输入
- Win30 至少具备基础字符键输入路径

### 6. RTOS 版本的程序集已重新拉平

随着 `de2shell` 最近增加了更多程序，`de2shell_rtos` 一度因为 makefile 未同步而链接失败。

当前已修复：

- 补入 `crypto.c`, `ps2.c`, `info.c`, `monitor.c`, `demo.c`
- 补入 `crypto_cli/crypto_aes.c`, `crypto_sha.c`, `crypto_sm.c`
- `de2shell_rtos/main.c` 已同步注册并暴露 12 个程序：
  - `hello`, `memtest`, `crypto`, `ps2`, `snake`, `life`, `info`, `monitor`, `demo`, `win30`, `conway_hw`, `pong_hw`

其中 `conway_hw` 和 `pong_hw` 为硬件加速程序（Conway 生命游戏硬件引擎、Pong 硬件引擎），尚未注册 CLI 命令，只能通过未来 CLI 命令扩展访问。

CLI 命令共 16 条（15 条注册 + 1 条 FreeRTOS+CLI 内置 `help`）：

| 主命令 | 功能 |
|--------|------|
| hello | LED chaser |
| memtest | SDRAM diagnostics |
| crypto | AES/SHA/SM4 CLI |
| ps2 | PS/2 keyboard test |
| snake | Snake game |
| info | System dashboard |
| expdemo | 11 course labs |
| startui | Win 3.0 GUI |
| stats | Task list + stack HWM |
| heapstat | Heap usage |
| cpustat | CPU usage per task |

| 别名 | 等价于 |
|------|--------|
| kbd | ps2 |
| conwaylife | life (程序存在，但无独立 CLI 命令) |
| riscvasm | monitor (程序存在，但无独立 CLI 命令) |
| gui | startui |

注意：`life` 和 `monitor` 程序有回调（`cli_life`, `cli_monitor`），但只通过别名 `conwaylife` / `riscvasm` 注册，没有主命令名。`demo` 程序映射到 `expdemo` 主命令。

## 当前已验证事实

### 软件构建

已成功在 Docker 中重新构建：

```text
docker run --rm -v "E:\Main\JuniorII\NonExam\FPGA\DE2Extra:/project" de2extra-builder \
  bash -lc 'export PATH=/opt/riscv/bin:$PATH && \
  cd /project/sw/app/de2shell_rtos && \
  make clean NEORV32_HOME=/project/neorv32 && \
  mkdir -p build && \
  make exe NEORV32_HOME=/project/neorv32'
```

最新结果：

```text
Memory utilization:
   text   data    bss    dec    hex
  73424     76  32640 106140  19e9c

Executable (EXE): 73500 bytes @ 0x01000000
```

### ELF 布局

关键 section / symbol：

- `.text` at `0x01000000`
- `.data` at `0x80000000`
- `.bss`  at `0x80000050`
- `.freertos_heap` at `0x01900000`, size `0x4000`
- `ucHeap` at `0x01900000`
- `__de2_framebuffer_base = 0x01800000`

### ISR 栈路径

当前 `FreeRTOSConfig.h` 已定义：

- `configISR_STACK_SIZE_WORDS = 256`

因此 RISC-V port 现在使用 `port.c` 内部静态 `xISRStack[]`，而不是依赖“复用 main 启动栈”的旧路径。`de2shell_rtos.ld` 中保留的 `__freertos_irq_stack_top` 目前不再是主路径。

## 当前剩余问题

### P0. 部署流程

V3 使用 bootloader-first 上传流程，不再需要每次改动软件都重跑 Quartus。

部署脚本 `run/deploy_de2shell_rtos.sh`：

```bash
./run/deploy_de2shell_rtos.sh inc        # 推荐: 增量 = 重编 app + 串口上传
./run/deploy_de2shell_rtos.sh app        # 等价于 inc
./run/deploy_de2shell_rtos.sh upload     # 仅上传当前 bin
./run/deploy_de2shell_rtos.sh fpga       # 重编 bootloader + Quartus + 烧录
./run/deploy_de2shell_rtos.sh full       # fpga + app upload
```

流程：
1. Docker cross-compile `sw/app/de2shell_rtos/` -> `neorv32_exe.bin`
2. `run/upload_de2os.py` 通过 UART 发送到 NEORV32 bootloader
3. Bootloader 写入 SDRAM `0x01000000` 并跳转执行

正常改 app 代码只需 `inc`。只有改 bootloader / CPU IMEM 配置 / 顶层 RTL 时才需要 `fpga` 或 `full`。

注意：`run/deploy_de2os.sh` 是另一套脚本，目标固件为 `sw/app/de2os/`（较简单的 FreeRTOS 测试），不是 `de2shell_rtos`。

### P1. Quartus / RTL 还没对这批最终改动做闭环验证

虽然软件已能构建，但以下 RTL 改动仍需在 `par/de2os/` 下重新跑一遍：

- `src/rtl/de2os_top.vhd`
- `src/rtl/periph/vga_text_terminal.vhd`
- `src/rtl/periph/vga_pixel_ctrl.vhd`
- `src/rtl/periph/sdram_ctrl.vhd`

当前还不能宣称“de2os_pixel_rtos 最终 bitstream 已稳定可复现”。

补充：

- 已确认旧的 `de2os.sta.rpt` 基本无效，原因是 `par/de2os/de2os.qsf` 引用的 `../constraints/de2extra.sdc` 在工程路径下原先缺失
- 因此旧报告只分析到了 `altera_reserved_tck`
- 现已把 `par/constraints/de2extra.sdc` 补回为仓库内已有的共享基线版本
- 下一次 Quartus / STA 必须重新生成，不能继续参考旧 `de2os.sta.rpt`

### P2. 板上稳定性未验证

尤其是以下组合尚未重新实测：

- ICACHE burst refill
- SDRAM CPU path
- VGA pixel fetch path
- FreeRTOS 多任务调度
- Win30 切像素模式

这部分必须以上板结果为准。

### P3. PS/2 目前主要是 ASCII 路径

现在 RTOS 输入队列只稳定传递“可解码为 ASCII 的键”。这对 shell 和一部分 GUI 交互够用，但还不等于完整键盘事件系统。

受限点：

- 方向键、功能键、组合键不一定完整穿透到 Win30
- `win30_desk.c` 当前 RTOS 路径主要消费 `char`

如果后面要让 GUI 的键盘体验完整，最好改成 richer event 而不是单字节字符。

### P4. 无双缓冲

像素模式仍是单 framebuffer。理论上会有撕裂风险，但这不是当前启动阻塞项。

## 下一步

1. 增量部署测试：`./run/deploy_de2shell_rtos.sh inc`，验证 bootloader 上传链路。
2. 等共享 RTL 不再被其他编译占用后，重新跑 `par/de2os/` Quartus 编译（`./run/deploy_de2shell_rtos.sh fpga`）。
3. 若 Quartus 通过，上板验证 `de2shell_rtos/neorv32_exe.bin`：
   - scheduler 是否正常启动
   - shell 是否可交互
   - `crypto/info/monitor/expdemo/startui` 是否能进入
   - Win30 是否真能切像素模式
   - PS/2 是否可用
4. 补 `conway_hw` / `pong_hw` 的 CLI 命令注册（当前只有程序回调，没有 CLI 入口）。
5. 考虑为 `life` / `monitor` 添加独立主命令名（当前仅通过别名 `conwaylife` / `riscvasm` 访问）。
6. 根据板测结果再决定是否需要：
   - 补 richer PS/2 事件通道
   - 做双缓冲
   - 继续收敛 ICACHE/SDRAM 稳定性
