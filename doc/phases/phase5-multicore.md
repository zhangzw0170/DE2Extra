# Phase 5: 多核扩展 (研究储备)

> 日期: 2026-05-23 | 状态: Research | 前提: Phase 1-3 完成后评估
> 本文档为纯调研，不纳入 6/15 deadline 范围。

## 调研结论

**NEORV32 原生支持 SMP 双核。** `neorv32_top.vhd` 实体有 `DUAL_CORE_EN : boolean := false` 类属参数，使能后在同一个 SoC 内实例化第二个同构 CPU 核心复合体。

---

## NEORV32 SMP 双核架构

### 硬件特性

| 特性 | 说明 |
|---|---|
| 核心数 | 2 (同构，共享总线) |
| 使能方式 | `DUAL_CORE_EN = true` 类属参数 |
| 总线支持 | 最多 3 个主设备 (2× CPU + 1× DMA) |
| 中断路由 | CLINT (Core Local Interruptor) 管理核间中断 |
| 原子扩展 | Zaamo (原子内存操作) + Zalrsc (LR/SC 保留集) |
| 缓存一致性 | 无硬件窥探 — 软件通过 FENCE 指令维护 |

### 软件启动

NEORV32 提供标准 SMP 引导机制:

```c
/* neorv32_smp.c — 核心 0 启动核心 1 */
neorv32_smp_launch(core1_entry_function);
```

- 核心 0 上电执行 `main()`，核心 1 在 WFI 状态等待
- 核心 0 调用 `neorv32_smp_launch()` 传递函数指针唤醒核心 1
- 两个核心共享同一地址空间 (IMEM/DMEM/SDRAM/外设)

### 同步原语

| 原语 | ISA 扩展 | 说明 |
|---|---|---|
| `LR` (Load Reserved) | Zalrsc | 加载并标记地址保留集 |
| `SC` (Store Conditional) | Zalrsc | 条件存储，保留集未被打破时成功 |
| `AMO*` (原子内存操作) | Zaamo | AMOSWAP/AMOADD/AMOAND/AMOOR 等 |
| `FENCE` | Base I | 内存屏障，确保存储可见性 |

### 资源开销估算

| 资源 | 单核 (当前) | 双核 (估算) | 增量 |
|---|---|---|---|
| LEs | ~4,650 | ~8,500 | +83% (CPU 复制) |
| M9K | ~56 | ~80 | +43% (额外 IMEM/DMEM 或共享) |
| DSP | ~15 | ~30 | +100% (每个 CPU 独立) |
| 占用率 (LEs) | ~4% | ~7.4% | Cyclone IV 仍有大量余量 |

### 适用场景

| 场景 | 说明 |
|---|---|
| 密码学加速 | 核心 0 跑 shell/显示，核心 1 专职加密运算 |
| Conway 生命游戏 | 双核并行计算，一代分两半同时算 |
| 音频处理 | 核心 0 系统，核心 1 音频 DMA + 处理 |
| Linux/SMP OS | 双核跑 uClinux 或 FreeRTOS SMP |

### 已知限制

1. **无缓存窥探**: 两个核心各自有私有缓存，软件必须用 `FENCE` 保证一致性
2. **总线仲裁开销**: 共享总线增加竞争，内存密集型场景加速比 < 2x
3. **IMEM 容量**: 当前 32KB IMEM 需要两个核心共享或各自配独立 IMEM (需增加 M9K)
4. **调试复杂度**: 双核调试需要 GDB 多线程支持 (PR #1450 修复了 SMP GDB 启动)

---

## 其他 RISC-V 多核方案参考

### VexRiscv 四核 (Artix-7)

- **平台**: VexRiscv (SpinalHDL) 在 Xilinx Artix-7 35KLUT 上实现 4 核 SMP
- **资源**: 占用 ~70% FPGA (24K LUT + 71 BRAM)
- **运行**: 完整 Linux SMP，4 核并发
- **对比**: NEORV32 更轻量，Cyclone IV 114K LE 足以容纳双核

### 学术: 功能单元共享多核

- **论文**: RISC-V 多核通过共享乘法器/除法器等功能单元节省 31.7% LUT
- **思路**: NEORV32 的 M 扩展 (MUL/DIV) 可在双核间时分复用
- **代价**: 增加仲裁逻辑复杂度，指令延迟变为非确定性

### Intel Nios II 多处理器参考

- **架构**: 4 个 Nios II 处理器 + 硬件 Mutex + 共享内存
- **同步**: 硬件 Mutex IP 核，占用极少 LE
- **对 NEORV32 的启发**: 可用 Zaamo AMOSWAP 实现等价 Mutex，无需额外 IP

---

## DE2Extra 双核实施路径 (如果要做的计划)

```
Phase 5a: 使能 DUAL_CORE_EN，验证双核启动
Phase 5b: 实现核间通信 (共享内存 + CLINT)
Phase 5c: 密码学卸载 — 核心 1 专职加密
Phase 5d: Conway 生命游戏双核并行
```

### Phase 5a 最小验证步骤

1. `neorv32_top.vhd` 设置 `DUAL_CORE_EN => true`
2. 启用 Zaamo + Zalrsc 扩展
3. 确认 CLINT 已实例化
4. 编写最小 SMP 测试: 核心 0 点亮 LED 低半，核心 1 点亮 LED 高半
5. 通过 UART 打印两个核心的 `hartid` 确认独立执行

### Phase 5a 资源需求

| 项目 | 说明 |
|---|---|
| 修改量 | ~3 个 VHDL 文件改动 (类属参数) |
| 软件 | 新建 `smp_test.c`，~50 行 |
| IMEM | 可能需要扩展到 64KB (双核共享或各自 32KB) |
| 预计时间 | 调试 ~4 小时 (主要是验证总线仲裁) |

---

## 参考资源

- **NEORV32 官方**: `neorv32/docs/` — SMP 启动流程、CLINT 寄存器映射
- **NEORV32 PR #1450**: 修复 SMP 双核 GDB 启动
- **RISC-V Atomic Extension Spec**: Zaamo/Zalrsc 指令语义
- **VexRiscv**: https://github.com/SpinalHDL/VexRiscv — 四核 SMP 参考
- **riscv-opcodes**: https://github.com/riscv/riscv-opcodes — AMO 指令编码
