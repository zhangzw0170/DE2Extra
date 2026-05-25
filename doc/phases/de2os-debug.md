# de2os 调试记录：从“SDRAM 执行无输出”到“ICACHE 关闭后可稳定启动”

> 日期: 2026-05-24 | 状态: 已定位到可启动基线，后续问题转入软件功能收敛

## 2026-05-24 最新结论

### 结果

- `de2os` 已不再处于“上传成功但无任何输出”的状态。
- 使用 `par/de2os/de2os.qpf` + `src/rtl/de2os_top.vhd`，并将 `ICACHE_EN` 设为 `false` 后，系统已可稳定启动。
- 已实测看到以下关键输出:

```text
Booting from 0x01000000...
LCD init done
Starting scheduler...
[gui] started
[crypto] started
[input] started
```

### 目前的判断

- `ELF entry` 与 `neorv32_exe.bin` header 的 `base_addr` 都是正确的 `0x01000000`，因此不是“跳错入口地址”。
- 当前最可能的根因，是 `ICACHE + SDRAM 取指` 这条路径存在问题；关闭 `ICACHE` 后，CPU 可以正常从 SDRAM 执行并进入 FreeRTOS 调度。
- 因此当前应把 `ICACHE_EN=false` 视为 `de2os` 的已知稳定基线，而不是最终性能配置。

### 对 `ICACHE` 问题的进一步收缩

当前更具体的怀疑点，不是“cache 参数本身错误”，而是 `sdram_ctrl` 的 CPU(50MHz) → SDRAM(100MHz) 请求 CDC 仍然残留一个对连续请求不够稳的角落：

- 之前为了修 `memtest`，请求/应答已经从脉冲跨域改成了 `toggle`
- 但 CPU 侧的 `req_shadow_*` 仍然可能在 100MHz 域真正锁存前，被下一笔请求提前覆盖
- 普通单次 load/store 不容易打到这个角落
- `ICACHE` 开启后，cache line refill 会发起一串锁住的连续取指访问，更容易触发这个 shadow 覆盖窗口

因此当前最强假设是：

- **ICACHE 失败的根因在“连续请求下的残余 CDC 风险”**
- **不是 entry point、不是 bootloader header、也不优先像是纯粹的 cache block 参数问题**

### 为什么偏偏是 `ICACHE` 更容易触发

NEORV32 这里的 `ICACHE` 不是“一次 miss 只多读一个 word”。

- 当前配置是 `CACHE_BLOCK_SIZE = 32B`
- 这意味着一次 instruction-cache miss 需要回填 `8` 个 `32-bit word`
- 同时 `CACHE_BURSTS_EN = false`
- 所以这 `8` 个 word 不是一个真正的外部 burst，而是 **8 次连续的 locked single-read**

也就是说，对外部总线和 SDRAM 控制器来说，`ICACHE` miss 的访问形态更接近：

```text
取第一条指令 miss
  → 发起第 1 次 SDRAM 读
  → 等 ack
  → 立刻发起第 2 次 SDRAM 读
  → 等 ack
  → ...
  → 连续做满 8 次
```

这和普通代码里零散的单次 load/store 很不一样。普通单次访问之间通常有更大的间隔，而 cache refill 会在很短时间内重复打这条路径，所以更容易暴露：

- 请求 shadow 在目标时钟域锁存前被下一笔覆盖
- 请求/应答 toggle 虽然没丢，但 source 侧保持窗口不够长
- 读数据回传刚好压在线路和状态机最紧的边界上

换句话说，**`ICACHE` 更像是“压力测试器”**，它把 SDRAM 控制器最怕的连续取指模式稳定地复现出来了。

### 当前对次要嫌疑点的判断

还有一个次要嫌疑点是：`neorv32_wrapper` 目前没有把 `xbus_cti/tag` 继续往板级互连和 SDRAM 控制器传。

- 这在“要不要支持真正外部 burst”时是重要问题
- 但对当前 `de2os` 不是第一优先级
- 因为当前硬件配置里 `CACHE_BURSTS_EN = false`
- 也就是说 `ICACHE` 本来就没有在对外发增量 burst，只是在做 locked single-read 序列

因此当前阶段更合理的排查顺序仍然是：

1. 先把 `sdram_ctrl` 在连续请求下的 CDC / 握手彻底做稳
2. 再考虑是否值得把 `cti/tag` 一路带出，为后续真正 burst 访问做准备

### 当前已知代价

- 关闭 `ICACHE` 会降低从 SDRAM 执行时的指令取值性能。
- 这会影响后续 benchmark 吞吐，但不会阻止系统启动和功能验证。
- 当前阶段优先级应是“先保证可启动、可观察、可继续修”，性能回补放到后续单独排查。

## 现象

1. Quartus 综合 + JTAG 烧录成功（早期记录基于 `ICACHE=true`）
2. UART 上传 `neorv32_exe.bin` 成功，bootloader 输出 `Booting from 0x01000000...`
3. **之后 115200 无任何输出**，LCD 只显示 `e`（bootloader execute 命令回显）
4. 当时 FreeRTOS 心跳未出现

## 环境

| 项目 | 值 |
|------|-----|
| FPGA | Cyclone IV E EP4CE115F29C7 (DE2-115) |
| Quartus | 23.1std Lite |
| CPU | NEORV32 RV32IMC + Zbkb/Zbkc/Zbkx/Zknd/Zkne/Zknh/Zksed/Zksh |
| 时钟 | 50MHz |
| BOOT_MODE | 0 (bootloader → SDRAM) |
| ICACHE | 64 blocks × 32B, bursts disabled |
| SDRAM 基地址 | 0x01000000 |
| DMEM 基地址 | 0x80000000 (16KB) |
| CLINT | 启用 (MTIMER @ 0xFFF4BFF8 / MTIMECMP @ 0xFFF44000) |
| Quartus 工程 | `par/de2os/de2os.qpf` (top=de2os_top) |
| 固件大小 | neorv32_exe.bin: 7116 bytes, elf.bin: 7100 bytes |

## 固件信息

```
neorv32_exe.bin: 7116 bytes (含 16-byte NEORV32 header)
elf.bin:         7100 bytes (flat binary, objcopy -O binary)
main.elf:        143168 bytes (ELF with debug info)
Entry point:     待确认 — 需 readelf 检查
.data / .bss:    0x80000000 (DMEM, 16KB)
工具链:          riscv-none-elf-gcc (Docker de2extra-builder)
ISA:             rv32imc_zicsr_zicntr_zifencei
```

## 启动流程分析

### 正常流程 (期望)

```
FPGA 配置 (JTAG)
  → NEORV32 bootloader 从 IMEM 启动
    → 19200 8N1 UART 输出 banner + countdown
    → 接收 'u' 命令 → 等待二进制数据
    → 接收 7116 bytes → 写入 SDRAM @ base_addr
    → 校验 checksum → OK
    → 接收 'e' 命令 → fence.i → mret to 0x01000000
      → crt0.S: _start
        → 设置 sp = __crt0_stack_top (0x80004000)
        → 设置 gp = __global_pointer$
        → 安装 __crt0_panic 为临时 trap handler
        → .data 拷贝: SDRAM → DMEM
        → .bss 清零
        → 调用 main()
          → neorv32_uart0_setup(115200, 0)
          → neorv32_uart0_puts("=== de2os: FreeRTOS on NEORV32 ===")
          → ... LCD init, FreeRTOS tasks ...
```

### 关键点: bootloader 如何跳转到固件

1. Bootloader 从 `neorv32_exe.bin` 头部读取 `base_addr` (4 bytes @ offset 4)
2. 将 flat binary 写入 SDRAM 从 `base_addr` 开始
3. 收到 `e` 命令后:
   - 执行 `fence.i` (指令缓存同步)
   - 执行 `mret` 跳转到 `base_addr` (= 0x01000000)

**如果 `base_addr` 不是 0x01000000 而是其他值, 跳转会到错误地址。**

## 可疑点分析 (按可能性排序)

### P1 [最高概率]: ELF 入口点错误 → exe header base_addr 错误

**机制**: `common.mk` 第 255 行构建 `neorv32_exe.bin`:
```makefile
$(IMAGE_GEN) -t exe \
  -b $(shell $(READELF) -h $(APP_ELF) | $(SED) -n 's/.*Entry point address: *//p') \
  -i $(APP_FLT) -o $@
```

`-b` 参数从 ELF 的 `Entry point address` 提取, 写入 exe header 的 `base_addr` 字段。

**风险**: 如果 `--defsym,__neorv32_rom_base=0x01000000` 没有正确传递给链接器, ELF 入口点会落在默认的 0x00000000 (IMEM), bootloader 会跳到 IMEM 里的 bootloader 自身代码区域, 立即崩溃。

**验证命令**:
```bash
# 在 Docker 里:
riscv-none-elf-readelf -h main.elf | grep "Entry point"
# 期望: Entry point address: 0x1000000
# 失败: Entry point address: 0x0

riscv-none-elf-readelf -S main.elf
# 检查 .text 是否在 0x01000000, .data 是否在 0x80000000

# 检查 exe header:
xxd neorv32_exe.bin | head -2
# Bytes 4-7 (little-endian) 应该是 00 00 00 01 (= 0x01000000)

# 检查 flat binary 大小:
ls -la elf.bin
# 应该是 ~7100 bytes; 如果 ~16MB, 说明 .text 在 0x0 而非 0x01000000
```

**注意**: Docker 构建命令 (`deploy_de2os.sh` 第 26 行) 运行:
```bash
cd /project/sw/app/de2os && make clean NEORV32_HOME=/project/neorv32 && make exe NEORV32_HOME=/project/neorv32
```
USER_FLAGS 在 makefile 中定义, 不依赖命令行传递, 应该正确。但需要验证。

### P2 [高概率]: crt0 startup 死在 .data 拷贝

**机制**: `crt0.S` 第 109-118 行:
```asm
# x7 = __crt0_copy_data_src_begin = LOADADDR(.data) (在 SDRAM 的 .rodata 尾部)
# x8 = __crt0_copy_data_dst_begin = ADDR(.data) (在 DMEM @ 0x80000000)
# x9 = __crt0_copy_data_dst_end   = ADDR(.data) + SIZEOF(.data)

beq  x7, x8, __crt0_data_copy_end   # 如果 src==dst, 跳过
bge  x8, x9, __crt0_data_copy_end   # 如果 section 为空, 跳过

__crt0_data_copy_loop:
  lw   x15, 0(x7)       # 从 SDRAM 读
  sw   x15, 0(x8)       # 写到 DMEM
  addi x7, x7, 4
  addi x8, x8, 4
  blt  x8, x9, __crt0_data_copy_loop
```

**分析**:
- 链接脚本 `neorv32.ld` 第 99-111 行: `.data : ALIGN(4) { ... } > ram AT > rom`
- `LOADADDR(.data)` = `.rodata` 末尾在 SDRAM (≈ 0x0100XXXX)
- `ADDR(.data)` = DMEM 起始 (0x80000000)
- src ≠ dst, 所以拷贝不会跳过
- 从 SDRAM 读需要 XBUS → wb_intercon → sdram_ctrl, 首次读可能触发 ICACHE miss

**如果 SDRAM 控制器在 bootloader 写入后的读取有时序问题**, `lw x15, 0(x7)` 可能会:
- 超时 (XBUS timeout 2048 cycles ≈ 41μs @50MHz) → 触发 bus error trap
- 返回错误数据 → .data 初始化不正确 → 后续代码崩溃

**验证**: 在链接后的 ELF 中检查符号:
```bash
riscv-none-elf-nm main.elf | grep -E "crt0_copy|crt0_bss|crt0_stack"
# 期望:
#   __crt0_copy_data_src_begin  在 0x0100XXXX (SDRAM)
#   __crt0_copy_data_dst_begin  在 0x8000XXXX (DMEM)
#   __crt0_stack_top            在 0x80004000 (DMEM 末尾)
```

### P3 [高概率]: ICACHE 首次取指失败

**机制**: CPU 从 SDRAM (0x01000000) 取第一条指令:
1. ICACHE miss → 发起 Wishbone 读请求到 XBUS
2. XBUS → wb_intercon → s0 (sdram_ctrl)
3. SDRAM 控制器执行 ACTIVATE + READ 时序
4. 数据返回 → ICACHE 填充 → CPU 继续执行

**风险**: ICACHE 配置为 64 blocks × 32B。每次 miss 需要 32 字节 (8 个 word) 的顺序读取。SDRAM 控制器的 BURST_LENGTH=1 (单 word 模式), 所以需要 8 次独立的 ACTIVATE+READ 操作。

如果第一次 SDRAM 读取的延迟超过 XBUS timeout (2048 cycles), CPU 收到 bus error, 跳到 `__crt0_panic` (无限 `wfi` 循环)。

**验证**: 禁用 ICACHE 测试:
```vhdl
-- de2os_top.vhd 第 231 行
ICACHE_EN => false,   -- 临时禁用 ICACHE
```
重新综合, 烧录, 上传。如果禁用 ICACHE 后能输出, 则 ICACHE 是问题所在。

**SDRAM 时序**: SDRAM 初始化需要 200μs, bootloader 运行时间远超此值, 所以 SDRAM 已就绪。SDRAM CAS latency = 3 clocks @ 100MHz = 60ns。从发起到返回第一个 word 约 80-120ns, 远小于 2048 cycle (41μs) timeout。理论上不应超时。

### P4 [中概率]: FreeRTOS IRQ 栈 / DMEM 布局冲突

**链接脚本内存布局** (`neorv32.ld` + `de2os.ld`):
```
MEMORY {
  rom (rx)  : ORIGIN = 0x01000000, LENGTH = 8M     (SDRAM)
  ram (rwx) : ORIGIN = 0x80000000, LENGTH = 16K    (DMEM)
}

DMEM 布局 (从低到高):
  .data     初始化的全局变量
  .bss      未初始化的全局变量 (含 FreeRTOS heap_4 的 ucHeap[8192])
  .heap     大小 = 0 (默认)
  ------
  FreeRTOS IRQ stack: __freertos_irq_stack_top = 0x80003C00 (距顶 1KB)
  Main stack:         __crt0_stack_top          = 0x80004000 (DMEM 末尾)
```

**DMEM 空间分析**:
- DMEM 总量: 16KB = 16384 bytes
- FreeRTOS heap: 8192 bytes (configTOTAL_HEAP_SIZE)
- Main stack: 从 0x80004000 向下增长 (最大 ~1KB 到 __freertos_irq_stack_top)
- IRQ stack: __freertos_irq_stack_top = 0x80003C00, 使用此值以下的空间

**任务栈分配** (从 heap_4 中分配):
- t_gui: 256 words = 1024 bytes
- t_crypto: 384 words = 1536 bytes
- t_input: 192 words = 768 bytes
- TCB 结构: 3 × ~80 bytes ≈ 240 bytes
- Queue: 8 × sizeof(crypto_msg_t=12) = 96 bytes + queue overhead ≈ 200 bytes
- **总计 heap 使用**: ~3864 bytes (在 8192 以内, 安全)

**但是**: .data + .bss 也占 DMEM 空间。如果 .data/.bss 太大, 会侵入 IRQ stack 区域。

**验证**:
```bash
riscv-none-elf-size main.elf
# 检查 data + bss 是否合理
riscv-none-elf-nm main.elf | grep -E "bss_end|data_end|heap_start"
```

### P5 [中概率]: crt0 早期 trap handler 是死循环

**机制**: `crt0.S` 第 36 行:
```asm
la x6, __crt0_panic    # 临时 trap handler
csrw mtvec, x6
```

`__crt0_panic` (第 224-226 行) 就是一个无限 `wfi` 循环:
```asm
__crt0_panic:
  wfi
  j __crt0_panic
```

**如果在 main() 之前发生任何异常 (bus error, illegal instruction, etc.), CPU 会进入这个死循环, 不会输出任何信息。** 这是设计如此的 — crt0 的 panic 不输出诊断信息, 因为 UART 可能还没初始化。

**改进方案**: 在 `__crt0_panic` 中加入最小诊断输出:
```asm
__crt0_panic:
  csrr t0, mcause
  csrr t1, mepc
  # 通过 GPIO LED 或 JTAG UART 输出 mcause/mepc
  wfi
  j __crt0_panic
```

### P6 [低概率]: LCD init 卡死导致 UART 无输出

**机制**: `main.c` 的执行顺序:
1. `neorv32_uart0_setup(115200, 0)` — 初始化 UART
2. `neorv32_uart0_puts("=== de2os: ...")` — 第一条输出 ← 如果能看到这个, 说明 UART 正常
3. `lcd_init()` — LCD 初始化, 包含 busy_wait 循环

**分析**: 如果 `lcd_wb.vhd` 的 busy 信号始终为高, `lcd_busy_wait()` 会死循环。但第 2 步的 UART 输出应该在 lcd_init 之前就发送了。

**除非固件在 main() 之前就崩溃了** (回到 P2/P3), 否则至少应该看到 "=== de2os:" 输出。

### P7 [低概率]: NEORV32 bootloader 的 SDRAM 写入不可靠

**分析**: Bootloader 使用 checksum 校验 (`~checksum` 在 exe header 中)。上传成功时 bootloader 应该打印了 "OK"。如果 checksum 通过, 说明写入数据正确。

但如果 SDRAM 存在 read-after-write 的一致性问题 (比如 SDRAM 刷新延迟), bootloader 写入后立即读取可能得到旧数据。

## 诊断步骤

### 第 1 步: 检查 ELF 入口点 (最高优先级)

```bash
cd sw/app/de2os
# 在 Docker 里执行:
docker run --rm -v "$(pwd):/project" de2extra-builder \
  bash -c 'export PATH=/opt/riscv/bin:$PATH && \
  riscv-none-elf-readelf -h /project/main.elf | grep "Entry point" && \
  riscv-none-elf-readelf -S /project/main.elf && \
  riscv-none-elf-nm /project/main.elf | grep -E "crt0_copy|crt0_bss|crt0_stack|freertos_irq"'
```

**期望输出**:
```
Entry point address: 0x1000000

.text    PROGBITS  01000000 ...
.rodata  PROGBITS  0100XXXX ...
.data    PROGBITS  80000000 ...
.bss     NOLOAD    8000XXXX ...

01000000 T _start
0100XXXX T main
8000XXXX D __crt0_copy_data_dst_begin
0100XXXX R __crt0_copy_data_src_begin
80004000 A __crt0_stack_top
80003c00 A __freertos_irq_stack_top
```

**如果入口点不是 0x01000000**: 链接器没有使用 SDRAM 地址, 需要检查 USER_FLAGS 是否传递到链接器。

```bash
# 检查 neorv32_exe.bin 头部:
xxd neorv32_exe.bin | head -2
# Byte 4-7 (LE) = base_addr
# 期望: 00 00 00 01 (= 0x01000000)
# 如果是: 00 00 00 00 (= 0x00000000), 则问题确认
```

### 第 2 步: 最小 hello-world 测试

创建 `sw/app/sdram_hello/` — 无 FreeRTOS, 无 LCD, 只有 UART:

**makefile**:
```makefile
MARCH = rv32imc_zicsr_zicntr_zifencei
MABI  = ilp32
EFFORT = -Os

USER_FLAGS += -Wl,--defsym,__neorv32_rom_base=0x01000000
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=8M
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k

NEORV32_HOME ?= ../../neorv32
include $(NEORV32_HOME)/sw/common/common.mk
```

**main.c**:
```c
#include <neorv32.h>

int main(void) {
    neorv32_uart0_setup(115200, 0);
    neorv32_uart0_puts("SDRAM hello\n");
    while (1) {
        neorv32_uart0_puts(".");
        for (volatile int i = 0; i < 2000000; i++);
    }
    return 0;
}
```

**如果 hello world 能输出**: 问题在 FreeRTOS 初始化
**如果 hello world 也无输出**: 问题在 crt0 / 链接器 / ICACHE / SDRAM 取指路径

### 第 3 步: 禁用 ICACHE 测试

编辑 `src/rtl/de2os_top.vhd`:
```vhdl
ICACHE_EN => false,   -- 临时禁用
-- 注释掉下面两行:
-- ICACHE_BLOCKS   => 64,
-- ICACHE_BLOCK_SZ => 32,
```

重新综合 (`par/de2os/de2os.qpf`), 烧录, 上传同一个 neorv32_exe.bin。

**如果禁用 ICACHE 后能输出**: ICACHE + SDRAM 的交互有问题, 需要检查 ICACHE 填充时序和 SDRAM 控制器的响应。

### 第 4 步: 检查 crt0 符号

```bash
riscv-none-elf-nm main.elf | grep crt0
```

关键符号:
- `__crt0_copy_data_src_begin` — 应在 SDRAM 范围 (0x0100XXXX)
- `__crt0_copy_data_dst_begin` — 应在 DMEM 范围 (0x8000XXXX)
- `__crt0_copy_data_dst_end`   — 应略大于 dst_begin
- `__crt0_stack_top`           — 应为 0x80004000

### 第 5 步: 反汇编入口点

```bash
riscv-none-elf-objdump -d main.elf | head -80
```

检查 `_start` 处的指令是否合理:
- `csrr x1, mhartid`
- `auipc x4, ...` + `addi x4, x4, ...` (加载 __crt0_stack_top)
- `andi x2, x4, -16` (对齐 sp)
- ...

### 第 6 步: build.sh 使用了错误的 Quartus 工程

`build.sh` 第 52 行硬编码 `par/de2extra.qpf`, 如果误用 `./build.sh app/de2os`, 会编译 `de2_115_top` (BOOT_MODE=2, 无 ICACHE) 而非 `de2os_top` (BOOT_MODE=0, 有 ICACHE)。

**当前状态**: de2os 使用独立的 `deploy_de2os.sh`, 直接调用 `par/de2os/de2os.qpf`, 应该不受此影响。但需要确认烧录的 .sof 是 `par/de2os/de2os.sof` 而非 `par/de2extra.sof`。

## 关键源文件参考

### 链接脚本分析

**`neorv32.ld`** (NEORV32 默认):
- `MEMORY { rom(rx): ORIGIN=__neorv32_rom_base, LENGTH=__neorv32_rom_size; ram(rwx): ... }`
- `.text` → `> rom`
- `.rodata` → `> rom`
- `.data` → `> ram AT > rom` (运行时在 RAM, 加载地址在 ROM)
- `.bss` → `> ram` (NOLOAD)
- 导出 crt0 符号: `__crt0_stack_top = ORIGIN(ram) + LENGTH(ram)` = 0x80004000

**`de2os.ld`** (补充脚本):
```
__freertos_irq_stack_top = ORIGIN(ram) + LENGTH(ram) - 1024;
```
= 0x80003C00

**`FreeRTOSConfig.h`** 关键值:
- `configCPU_CLOCK_HZ = 50000000`
- `configMTIME_BASE_ADDRESS = NEORV32_CLINT_BASE + 0xBFF8` (需检查 NEORV32_CLINT_BASE 的值)
- `configMTIMECMP_BASE_ADDRESS = NEORV32_CLINT_BASE + 0x4000`
- `configTICK_RATE_HZ = 100`
- `configTOTAL_HEAP_SIZE = 8192`
- `configMINIMAL_STACK_SIZE = 192`
- `configISR_STACK_SIZE_WORDS` **未定义** → 使用 linker symbol `__freertos_irq_stack_top`

### crt0 启动流程 (neorv32/sw/common/crt0.S)

```
_start:
  csrr x1, mhartid          # 检查核心 ID (应为 0)
  la x4, __crt0_stack_top   # sp = DMEM 末尾
  andi x2, x4, -16          # 16 字节对齐
  la x3, __global_pointer$  # gp
  li x5, 0x1800             # mstatus.MPP = machine mode
  csrw mstatus, x5
  la x6, __crt0_panic       # 临时 trap handler (死循环!)
  csrw mtvec, x6
  csrw mie, zero            # 禁用所有中断

  # 加载 .data 拷贝和 .bss 清零的地址参数
  la x7, __crt0_copy_data_src_begin   # SDRAM
  la x8, __crt0_copy_data_dst_begin   # DMEM
  la x9, __crt0_copy_data_dst_end
  la x10, __crt0_bss_start
  la x11, __crt0_bss_end

  # 清零 x12-x31

  # SMP check (单核跳过)

  # .data 拷贝: x7 → x8, 循环直到 x8 >= x9
  # .bss 清零: x10 写 0, 循环直到 x10 >= x11

  # 调用构造函数
  # fence; fence.i
  # jalr main()

  # main 返回后:
  # 禁用中断, 重装 panic handler, ebreak, wfi 死循环
```

### NEORV32 exe header 格式 (image_gen.c)

```
Offset  Size  Field
0x00    4     signature  = 0x214F454E ("NEOV" little-endian → "NEO!")
0x04    4     base_addr  = ELF entry point (从 readelf 提取)
0x08    4     size       = flat binary 大小 (padding to 4-byte align)
0x0C    4     checksum   = ~sum(all 32-bit words in flat binary)
0x10    ...   flat binary data
```

### de2os_top.vhd 的 ICACHE 配置

```vhdl
-- neorv32_wrapper 实例化, 第 230-234 行
BOOT_MODE       => 0,
ICACHE_EN       => false
```

### FreeRTOS port.c 的 IRQ 栈初始化

```c
// port.c 第 76-77 行 (configISR_STACK_SIZE_WORDS 未定义路径)
extern const uint32_t __freertos_irq_stack_top[];
const StackType_t xISRStackTop = ( StackType_t ) __freertos_irq_stack_top;
```

### portASM.S trap handler 的 ISR 栈切换

```asm
// portASM.S 第 362-363 行
load_x sp, xISRStackTop     # 切换到 ISR 栈 (0x80003C00)
```

## 已确认可工作的部分

- de2shell (BOOT_MODE=2, IMEM 直接执行) — 完全正常
- SDRAM 控制器 — memtest PASS (4096-word dense + 31 sparse)
- CLINT — neorv32_wrapper.vhd 中 `IO_CLINT_EN => true`
- NEORV32 bootloader — 19200 8N1, 接受上传, 校验 OK, 跳转 OK
- Docker 交叉编译 — 生成 ELF, make exe 成功
- Quartus 综合 — par/de2os/de2os.sof 编译 0 error
- de2os 启动链路 — 在 `ICACHE_EN=false` 基线下已可进入 `main()`、完成 `lcd_init()`、启动 FreeRTOS scheduler 和 3 个任务

## 相关文件清单

```
sw/app/de2os/
├── makefile                  # USER_FLAGS 定义 rom_base/rom_size/ram_size
├── FreeRTOSConfig.h          # configCPU_CLOCK_HZ=50000000, CLINT addresses
├── de2os.ld                  # __freertos_irq_stack_top = ORIGIN(ram) + LENGTH(ram) - 1024
├── main.c                    # 入口 + LCD 驱动 + FreeRTOS 任务创建
├── t_gui.c / t_crypto.c / t_input.c
├── freertos/
│   ├── portable/GCC/RISC-V/
│   │   ├── port.c            # xPortStartScheduler, vPortSetupTimerInterrupt, xISRStackTop
│   │   ├── portASM.S         # trap handler, task switch, mtimer ISR
│   │   └── portContext.h     # 上下文保存/恢复宏, portCONTEXT_SIZE
│   └── portable/MemMang/
│       └── heap_4.c          # pvPortMalloc 使用 configTOTAL_HEAP_SIZE
└── neorv32_exe.bin           # 上传用固件 (7116 bytes)

neorv32/sw/common/
├── common.mk                 # make exe: readelf → image_gen → neorv32_exe.bin
├── crt0.S                    # 启动代码: sp, gp, .data copy, .bss clear, main()
└── neorv32.ld                # 默认链接脚本: MEMORY, SECTIONS, crt0 symbols

neorv32/sw/image_gen/
└── image_gen.c               # exe header: signature, base_addr, size, checksum

src/rtl/
├── de2os_top.vhd             # 独立顶层 (BOOT_MODE=0, ICACHE 现阶段关闭)
├── neorv32_wrapper.vhd       # CPU 配置封装
├── periph/lcd_wb.vhd         # LCD Wishbone 控制器 @ 0xF000B000
└── bus/wb_intercon.vhd       # s0-s5 (s5 LCD)

par/de2os/
├── de2os.qpf / de2os.qsf    # 独立 Quartus 工程
└── de2os.sof                 # 烧录文件

run/
├── deploy_de2os.sh           # 自动化: 编译 + 烧录 + 上传
└── upload_de2os.py           # UART 上传脚本
```

## 推荐修复方案

### 方案 A: 验证并修复入口点 (如果 P1 确认)

确认 `readelf -h main.elf` 的入口点是 0x01000000。如果不是:
- 检查 Docker 中 makefile 的 USER_FLAGS 是否被正确展开
- 检查 common.mk 的 `LD_SCRIPT` 是否被 `-T de2os.ld` 覆盖导致 neorv32.ld 没有被使用

### 方案 B: 最小 hello-world 排除法

创建 `sw/app/sdram_hello/`, 只保留 UART 输出, 无 FreeRTOS 无 LCD:
- 如果能输出 → 问题在 FreeRTOS (P4)
- 如果不能输出 → 问题在 crt0/ICACHE/SDRAM (P2/P3)

### 方案 C: 禁用 ICACHE (已验证有效)

将 `de2os_top.vhd` 中 `ICACHE_EN => false` 后，`de2os` 已能够稳定启动。后续应把这条配置作为调试与软件修复的基线。

### 方案 D: 在 crt0 panic 中加入诊断

修改 crt0.S 的 `__crt0_panic`, 通过 GPIO LED 显示 mcause/mepc:
```asm
__crt0_panic:
  csrr t0, mcause
  # 将 t0[3:0] 输出到 LEDR[3:0]
  lui  t1, 0xF0010         # GPIO output base address
  sw   t0, 0(t1)           # 写 GPIO.out
  wfi
  j __crt0_panic
```
