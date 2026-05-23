# RTOS 选型分析 for NEORV32

> 日期: 2026-05-23
> 目标: RV32IMC bare-metal, IMEM 32KB, DMEM 16KB, SDRAM 128MB 可选

## 硬约束

| 约束 | 值 | 影响 |
|---|---|---|
| ISA | RV32IMC | 无 MMU, 无 S-mode/U-mode, 仅 M-mode |
| IMEM | 32KB | RTOS 内核 + 任务代码必须在此 |
| DMEM | 16KB | 任务栈 + 系统堆 |
| SDRAM | 128MB | 数据段可放, 但不能执行代码 (除非改 linker) |
| 中断 | 仅 mext_irq 一根外部中断线 | 需要软件中断分发 |
| Timer | CLINT mtime (64-bit @CPU clock) | 够用 |

---

## 候选对比

| RTOS | ROM | RAM | 抢占 | 优先级 | RISC-V 官方支持 | 社区 | 适合? |
|---|---|---|---|---|---|---|---|
| **FreeRTOS** | ~6KB | ~2KB+栈 | ✅ | ✅ | ✅ v10.3+ | 最大 | ⭐⭐⭐ |
| **Atomthreads** | ~2KB | ~512B+栈 | ✅ | ✅ | ❌ 需移植 | 小 | ⭐⭐⭐ |
| **Zephyr** | ~50KB | ~20KB | ✅ | ✅ | ✅ | 大 | ❌ 太重 |
| **NuttX** | ~40KB | ~16KB | ✅ | ✅ | ✅ | 中 | ❌ 需 MMU |
| **RIOT-OS** | ~15KB | ~4KB | ✅ | ✅ | ✅ | 中 | ⚠️ IoT 偏向 |
| **TNKernel** | ~3KB | ~1KB | ✅ | ✅ | ❌ 需移植 | 极小 | ⭐⭐ |
| **de2shell (现状)** | ~10KB | ~8KB | ❌ 协作式 | ❌ | — | — | 基准 |

---

## 详评

### 1. FreeRTOS — 最成熟，但可能过头

**优势**:
- RISC-V 官方 port 已有 (`FreeRTOS/Source/portable/GCC/RISC-V/`)
- 抢占式多任务、优先级、互斥锁、信号量、队列、软件定时器全套
- 社区最大，bug 最少
- v10.3+ 支持 CLINT mtime 做 tick，不需要额外定时器硬件

**劣势**:
- 内核 ~6KB，配上 4 个任务 + 队列 → ROM ~12KB+
- 每个任务默认栈 512B-1KB → 4 任务 + 空闲任务 ≈ 5-10KB RAM
- 内存紧张 (DMEM 16KB 勉强，用 SDRAM 则够)
- 移植工作: `port.c` (上下文切换), `portasm.S` (汇编), `FreeRTOSConfig.h` 需适配 NEORV32 的 `mext_irq` 中断入口

**移植步骤**:
1. 复制 `FreeRTOS/Source/portable/GCC/RISC-V/` → `sw/lib/freertos/port/`
2. 修改 `portasm.S` 中的 `SW`/`LW` 为 NEORV32 CSR 操作 (mepc, mstatus, mtvec)
3. `FreeRTOSConfig.h`: `configCPU_CLOCK_HZ=50_000_000`, `configTICK_RATE_HZ=1000`
4. 链接脚本: IMEM 放 `vPortStartFirstTask` 入口，DMEM/SDRAM 放 `.bss` + 堆

**现有移植参考**: NEORV32 论坛上有 FreeRTOS 移植成功的案例，社区已踩过坑。

### 2. Atomthreads — 极简，最可能成功

**优势**:
- **仅 2KB ROM + 512B RAM** — 轻到可以放进 IMEM 预留空间
- 纯 C 实现，无汇编 port (用 `setjmp/longjmp` 或手写上下文切换)
- API 简洁: `threadCreate`, `semTake`, `mutexLock`, `timerStart`
- 学习成本极低

**劣势**:
- 没有 RISC-V 官方 port → 需要自己写上下文切换 (~50 行汇编)
- 社区小，bug 需自行修复
- 无优先级继承、无 tickless idle、无 MPU 支持

**移植步骤**:
1. 写 `arch/riscv/atomport.c` (保存/恢复上下文, 栈初始化, PendSV 模拟)
2. 用 CLINT mtime 中断做 tick
3. 用 mext_irq 做软件中断触发上下文切换
4. 4 个 API 头文件直接拷入

### 3. 自定义抢占调度器 — 最贴合需求

如果只需要"几个任务轮流跑 + 定时器打断"，自己写比移植更快。

**设计**:
```
tasks[8] = { crypto, snake, life, dashboard, idle, ... }
systick ISR: 保存当前上下文 → 选下一个就绪任务 → 恢复上下文 → mret
```

**优势**: 完全控制，零依赖。如果只做 4-8 个任务的协作+定时抢占，200 行 C + 50 行汇编即可。

**劣势**: 没有互斥锁/信号量/队列 → 需要自己实现临界区保护。

---

## 场景匹配

| 场景 | de2shell 够不够 | 推荐 |
|---|---|---|
| 键入命令 → 顺序执行 → 返回 shell | ✅ 够了 | de2shell |
| 仪表盘后台刷新 + 密码学前台计算 | ✅ 够了 (轮询 update) | de2shell |
| PS/2 中断接收 + shell 命令行 | ✅ 加键盘缓冲即可 | de2shell |
| **音频流连续输出 + 同时处理键盘** | ❌ 不够 | FreeRTOS 或 Atomthreads |
| **TCP/IP 后台收发 + shell 前台** | ❌ 不够 | FreeRTOS |

---

## 推荐路线

| 优先级 | 方案 | 何时 | 为什么 |
|---|---|---|---|
| **现在** | de2shell 协作式 | 6/15 前 | 够用，零风险 |
| **Phase 4** | Atomthreads | 6/15 后 | 如果做音频+SD卡需要多任务并发 |
| **Phase 5 (?)** | FreeRTOS | 如果做以太网 | 有现成 LWIP 集成 |

**现在不适合上 FreeRTOS 的真实原因**：不是做不了，而是 6/15 前没有足够的并发场景来体现它的价值。音频是第一个"不得不并发"的场景——I2S 需要定时喂数据、键盘要响应、VGA 要刷新——到那时上 Atomthreads 或 FreeRTOS 才划算。

如果非要现在过把瘾，Atomthreads 一个晚上就能移植完——代码量小，踩坑范围可控。

---

## 后期迁移成本分析

### de2shell `program_t` 是天然的 RTOS 任务原型

```c
// 现状: 协作式轮询
typedef struct {
    void (*init)(void);
    void (*update)(void);      // 每帧调用
    void (*input)(char c);     // 键盘输入
    int  (*finish)(void);      // 返回 1 = 结束
} program_t;

// 迁 FreeRTOS: 完全兼容
void vTaskSnake(void *params) {
    prog_snake.init();
    while (1) {
        char c; xQueueReceive(kb_queue, &c, portMAX_DELAY);
        prog_snake.input(c);
        prog_snake.update();
        if (prog_snake.finish()) break;
    }
    vTaskDelete(NULL);
}
```

### 改动范围

| 文件 | 改动 | 说明 |
|---|---|---|
| `main.c` | 重写 | 用 `xTaskCreate` 替代 `while(1) { prog->update() }` |
| `vga_hal.c` | +3 行 | VGA buffer 写操作套 `xSemaphoreTake/Give` |
| `snake.c` ~ `exp12.c` (9 个程序) | **零改动** | `init/update/input/finish` 回调完全不变 |
| `crypto_cli/` | **零改动** | Phase 2a 独立编译，不受影响 |
| VHDL (`*.vhd`) | **零改动** | 纯硬件层不感知调度方式 |

### 迁移代价

| 方案 | 移植 port | 改 C 代码 | 总时间 |
|---|---|---|---|
| Atomthreads | 半天 (写 50 行 asm) | 半天 (重写 main.c) | 1 天 |
| FreeRTOS | 1-2 天 (中断分发适配) | 半天 (重写 main.c) | 1.5-2.5 天 |
| 自定义调度器 | 1 天 | 半天 | 1.5 天 |

### 决定

**先裸机完成 Phase 2b+3 上板联调**。后期心血来潮想移植 FreeRTOS，9 个 C 程序文件一个不用改，重写一个 `main.c` 即可。这份文档就是未来的迁移指南。
