# de2os / de2shell_rtos 内存分布表

> 日期: 2026-05-25
> 适用对象: `par/de2os/` + `sw/app/de2shell_rtos/`
> 用途: 记录当前 `de2os` 硬件和 `de2shell_rtos` 固件的地址规划，避免后续新增功能时撞区

## 1. 总览

当前 `de2os` 方案里有三类存储/地址空间：

1. NEORV32 片上 `IMEM`
2. NEORV32 片上 `DMEM`
3. 板外 `SDRAM` + MMIO 外设空间

对 `de2shell_rtos` 来说：

- 应用代码不再主要受 `IMEM 64KB` 限制
- `.text/.rodata` 运行在 SDRAM `0x01000000`
- `.data/.bss` 仍在 DMEM `0x80000000`
- FreeRTOS 动态堆单独放在 SDRAM `0x01900000`

## 2. CPU 片上存储

### IMEM

| 项目 | 值 |
|------|----|
| 配置位置 | `src/rtl/de2os_top.vhd` |
| 配置值 | `IMEM_SIZE => 64*1024` |
| 大小 | 64 KB |
| 作用 | NEORV32 片上指令存储 |
| 当前用途 | 主要供 bootloader / CPU 本体使用，不承载 `de2shell_rtos` 主应用镜像 |

说明：

- `de2os` 顶层使用 `BOOT_MODE => 0`
- `de2shell_rtos` 主程序通过 bootloader 上传到 SDRAM，再从 SDRAM 执行
- 因此当前主程序体积不再受 64KB IMEM 上限直接限制

### DMEM

| 项目 | 值 |
|------|----|
| 配置位置 | `src/rtl/de2os_top.vhd` |
| 配置值 | `DMEM_SIZE => 16*1024` |
| 大小 | 16 KB |
| 运行基址 | `0x80000000` |
| 当前用途 | `.data` / `.bss` / 小型全局对象 / 栈 |

当前关键符号：

| 符号 | 地址 | 说明 |
|------|------|------|
| `__freertos_irq_stack_top` | `0x80003C00` | linker symbol，保留但当前不是主要 ISR 栈来源 |
| `__crt0_stack_top` | `0x80004000` | 启动栈顶 / DMEM 顶部 |

说明：

- 当前 `FreeRTOSConfig.h` 已定义 `configISR_STACK_SIZE_WORDS = 256`
- 因此 RISC-V port 会优先使用 `port.c` 内部静态 `xISRStack[]`
- `__freertos_irq_stack_top` 目前更接近兼容性保留符号

## 3. SDRAM 地址规划

### SDRAM 总区间

| 项目 | 值 |
|------|----|
| 基址 | `0x01000000` |
| 大小 | 128 MB |
| 结束地址 | `0x08FFFFFF` |
| 来源 | `src/rtl/lib/de2extra_pkg.vhd` / `wb_intercon.vhd` |

当前系统实际只用了很小一部分。

### 当前已规划区段

| 地址范围 | 大小 | 用途 | 当前状态 |
|----------|------|------|----------|
| `0x01000000` 起 | 当前镜像约 `73.5 KB` | `de2shell_rtos` 应用镜像 (`.text/.rodata` + load image) | 已使用 |
| `0x01800000` 起 | `307200 B` (`640*480*1`) | VGA 8-bit framebuffer | 已保留 |
| `0x01900000` 起 | `16 KB` | FreeRTOS heap (`ucHeap`) | 已使用 |
| `0x01A00000` 以后 | 未定 | 预留给未来扩展，例如 SDRAM-backed demo / 双缓冲 / 资源区 | 建议保留 |

### 3.1 应用镜像区

| 项目 | 值 |
|------|----|
| 入口地址 | `0x01000000` |
| 链接配置 | `__neorv32_rom_base=0x01000000` |
| ROM 大小配置 | `__neorv32_rom_size=128M` |
| 最新 `EXE` 大小 | `73500 bytes` |
| 最新 `.text` | `73424 bytes` |

说明：

- 这里的“ROM”在 `de2os` 场景实际指 SDRAM 中的可执行区
- bootloader 会把 `neorv32_exe.bin` 上传到这里并跳转执行

### 3.2 framebuffer 区

| 项目 | 值 |
|------|----|
| 基址 | `0x01800000` |
| 符号 | `__de2_framebuffer_base` |
| 分辨率 | `640x480` |
| 像素格式 | `8-bit RGB332` |
| 大小 | `307200 bytes` (`0x4B000`) |

说明：

- 这块区域原先不能和程序入口重叠
- 当前已经显式从 `0x01000000` 挪开，避免 GUI 写像素覆盖程序代码

建议按下列边界看待这块区：

| 起点 | 终点 | 说明 |
|------|------|------|
| `0x01800000` | `0x0184AFFF` | framebuffer 实际像素数据 |
| `0x0184B000` 以后 | 暂未使用 | 但建议不要随意挤入新功能，除非重新做统一规划 |

### 3.3 FreeRTOS heap 区

| 项目 | 值 |
|------|----|
| 基址 | `0x01900000` |
| 符号 | `__de2_freertos_heap_base` |
| 实际对象 | `ucHeap` |
| 大小 | `16 KB` (`0x4000`) |
| section | `.freertos_heap` |

说明：

- 这块是为了解决 DMEM 16KB 不足的问题，专门把 FreeRTOS 动态堆挪到 SDRAM
- 当前位置与 framebuffer、代码区都已经分开

地址范围：

| 起点 | 终点 | 说明 |
|------|------|------|
| `0x01900000` | `0x01903FFF` | FreeRTOS heap 当前保留区 |

## 4. 当前软件构建占用

基于 `sw/app/de2shell_rtos/main.elf` 最新构建：

| 项目 | 大小 |
|------|------|
| `.text` | `73424 bytes` |
| `.data` | `76 bytes` |
| `.bss` | `32640 bytes` |
| `EXE` 镜像 | `73500 bytes` |

需要特别注意：

- `.bss` 数值看起来很大，但其中包含了被放进 SDRAM section 的 `ucHeap`
- 不能简单把 `.bss=32640` 理解为“DMEM 需要 32KB”
- 真正的 section 分布是：
  - `.data` at `0x80000000`
  - `.bss`  at `0x80000050`
  - `.freertos_heap` at `0x01900000`

## 5. MMIO 地址空间

当前 `de2os` 使用的主要外设窗口如下。

| 基址 | 大小 | 用途 |
|------|------|------|
| `0xF0000000` | 8 KB | VGA 文本终端 + 像素控制寄存器 |
| `0xF0008000` | 4 KB | PS/2 控制器 |
| `0xF0009000` | 4 KB | Timer |
| `0xF000A000` | 4 KB | INTC |
| `0xF000B000` | 4 KB | LCD Wishbone |
| `0xF000C000` | 4 KB | IR 接收器 |
| `0xF000D000` | 4 KB | DDS |
| `0xF000E000` | 4 KB | SD card |
| `0xF000F000` | 4 KB | NTT 加速器 |
| `0xF0010000` | 4 KB | ExpDemo |
| `0xF0011000` | 4 KB | PONG |
| `0xF0012000` | 4 KB | Conway |

### VGA 子区

当前 VGA 窗口内部又分成两段：

| 偏移 | 用途 |
|------|------|
| `< 0x1F80` | 文本终端窗口 / 文本控制寄存器 |
| `0x1F40..0x1F54` | 文本模式控制寄存器 |
| `0x1F80..` | 像素控制寄存器 |

当前 `fb_hal.c` 用到：

| 地址 | 含义 |
|------|------|
| `0xF0001F80` | pixel mode enable |
| `0xF0001F84` | framebuffer base word address |

## 6. Exp4 与 SDRAM 是否冲突

当前不会。

原因：

- `Exp4` 走的是 `src/rtl/exp/adapt_exp4.vhd`
- 内部实例化 `ram_top`
- `ram_top` 当前使用的是本地 `dpram`
- 它不是 SDRAM-backed 设计

也就是说：

- `de2os` 的代码/heap/framebuffer 用外部 SDRAM
- `Exp4` 的实验 RAM 用 FPGA 片上 BRAM

两者当前互不重叠。

## 7. 后续地址规划建议

如果后面要继续往 SDRAM 塞新东西，建议按这个顺序预留：

| 建议起点 | 建议用途 |
|----------|----------|
| `0x01000000` | 程序镜像 |
| `0x01800000` | framebuffer A |
| `0x01880000` | framebuffer B（若启用双缓冲） |
| `0x01900000` | FreeRTOS heap |
| `0x01A00000` | 未来的 SDRAM-backed demo / 资源区 / 大对象缓冲区 |

原则：

1. 不要再把任何像素缓冲放回 `0x01000000`
2. 不要让实验程序“临时借用” FreeRTOS heap 区
3. 如果 `Exp4` 将来改成 SDRAM-backed，必须手工给它固定区段，不能依赖运行时“自动分配”

## 8. 一页版摘要

| 区域 | 地址 | 大小 | 当前用途 |
|------|------|------|----------|
| IMEM | 片上 | 64 KB | bootloader / CPU 指令存储 |
| DMEM | `0x80000000` | 16 KB | `.data/.bss/栈` |
| SDRAM | `0x01000000` | 128 MB | 主应用执行区 |
| App image | `0x01000000` 起 | `~73.5 KB` | `de2shell_rtos` 镜像 |
| Framebuffer | `0x01800000` 起 | `~300 KB` | VGA 像素缓冲 |
| FreeRTOS heap | `0x01900000` 起 | `16 KB` | `ucHeap` |
| Exp4 RAM | 片上 BRAM | `32x8` | 实验 4，本地 RAM，不占 SDRAM |
