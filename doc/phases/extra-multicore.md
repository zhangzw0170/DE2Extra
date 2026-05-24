# Extra: 多核研究储备

> 日期: 2026-05-23 | 状态: Research | 优先级最低 — V3 稳定后若有余力再做 demo
>
> **方向偏好**: 混合架构 — VexRiscv 跑 OS (主机) + NEORV32 跑密码学 (协处理器)，
> 通过共享内存通信。NEORV32 同构 SMP 双核作为轻量备选。
>
> **备注 (2026-05-24)**: 资源允许扩展到更多核心，但 NEORV32 内置 SMP 仅支持双核
> （总线最多 3 master）。4/8 核需多实例 NEORV32 + 自定义仲裁器，且 SDRAM 带宽是
> 主要瓶颈——8 核抢一个 SDRAM 控制器，内存密集型加速比可能 < 2x。如果 SDRAM 带宽
> 问题能解决（如多 bank 交叉存取），4 核方案值得尝试：核心 0 跑 FreeRTOS + GUI，
> 核心 1 跑密码学，核心 2 跑输入处理，核心 3 跑网络/存储。

## 调研结论

**NEORV32 原生支持 SMP 双核。** `neorv32_top.vhd` 实体有 `DUAL_CORE_EN : boolean := false` 类属参数，使能后在同一个 SoC 内实例化第二个同构 CPU 核心复合体。

**更有前景的方向**是混合架构: VexRiscv 做主机 (跑 Linux，负责网络/文件系统/UI)，NEORV32 做密码学协处理器 (Zk* 硬件指令加速 AES/SHA/SM4/SM3)。两者通过共享内存 + 命令队列通信，类似工业界"主机 + 专用加密引擎"的模式。

---

## 方案 A: VexRiscv (主机) + NEORV32 (密码学协处理器)

### 架构

```
┌─────────────────────────────────────────────────┐
│                  Cyclone IV EP4CE115             │
│                                                  │
│  ┌──────────────┐    ┌──────────────────────┐    │
│  │  VexRiscv    │    │  NEORV32             │    │
│  │  主机 / OS   │    │  密码学协处理器      │    │
│  │  - Linux     │    │  - Zk* 硬件加速      │    │
│  │  - 网络/存储 │    │  - AES/SHA/SM4/SM3   │    │
│  │  - 用户界面  │    │  - TRNG 真随机       │    │
│  └──────┬───────┘    └──────────┬───────────┘    │
│         │                       │                │
│    ┌────┴───────────────────────┴────┐           │
│    │     共享 SDRAM (命令队列)       │           │
│    └─────────────────────────────────┘           │
└─────────────────────────────────────────────────┘
```

### 设计思路

- VexRiscv 跑 Linux，提供网络栈、文件系统、SSH 等完整 OS 服务
- NEORV32 裸机运行，专注密码学运算，利用 Zk* 指令加速
- 两者通过 SDRAM 共享内存通信: VexRiscv 写入加密请求 → NEORV32 轮询取任务 → 完成后写回结果 → VexRiscv 读走
- 类似工业界"主机 + 专用加密引擎"模式 (如 ARM + Crypto Engine)

### 优势

- **职责分离**: OS 复杂度交给 VexRiscv (有 MMU + Linux 主线支持)，密码学性能交给 NEORV32 (Zk* 硬件)
- **资源可行**: VexRiscv Linux 配置 ~15K LUT + NEORV32 ~5K LUT，Cyclone IV 占 ~17%
- **现有成果复用**: NEORV32 的 crypto_cli 代码、Zk* 实现直接迁移为协处理器固件

### 挑战

- **总线仲裁**: 两套 CPU 总线接口需要 Wishbone 仲裁器
- **内存共享**: SDRAM 需要分时复用或分区，缓存一致性需软件保证
- **工具链不同**: VexRiscv 用 SpinalHDL (Scala) 生成 Verilog，NEORV32 是手写 VHDL，混合 RTL 集成需要顶层包装
- **开发复杂度**: 两套交叉编译工具链、两套软件栈

### VexRiscv 资源参考

- **平台**: VexRiscv (SpinalHDL) 在 Artix-7 35KLUT 上实现 4 核 SMP Linux
- **资源**: 单核 Linux 配置 ~15K LUT + 40 BRAM
- **仓库**: https://github.com/SpinalHDL/VexRiscv
- **特点**: 可配置流水线深度、MMU、缓存大小、中断控制器

---

## 方案 B: NEORV32 同构 SMP 双核

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

### 已知限制

1. **无缓存窥探**: 软件必须用 `FENCE` 保证一致性
2. **总线仲裁开销**: 内存密集型场景加速比 < 2x
3. **IMEM 容量**: 32KB 需要共享或扩展到 64KB
4. **调试复杂度**: 双核调试需要 GDB 多线程支持 (PR #1450 已修复)

### 最小验证步骤 (如果要做)

1. `neorv32_top.vhd` 设置 `DUAL_CORE_EN => true`
2. 启用 Zaamo + Zalrsc 扩展
3. 确认 CLINT 已实例化
4. 编写最小 SMP 测试: 核心 0 点亮 LED 低半，核心 1 点亮 LED 高半
5. 预计调试 ~4 小时

---

## 其他多核参考

### 学术: 功能单元共享多核

- RISC-V 多核通过共享乘法器/除法器节省 31.7% LUT
- NEORV32 的 M 扩展可在双核间时分复用
- 代价: 增加仲裁逻辑，指令延迟非确定性

### Intel Nios II 多处理器

- 4 个 Nios II + 硬件 Mutex + 共享内存
- 可用 Zaamo AMOSWAP 实现等价 Mutex，无需额外 IP

---

## 参考资源

- **NEORV32 官方**: `neorv32/docs/` — SMP 启动流程、CLINT 寄存器映射
- **NEORV32 PR #1450**: 修复 SMP 双核 GDB 启动
- **VexRiscv**: https://github.com/SpinalHDL/VexRiscv — 可配置 RISC-V 处理器
- **RISC-V Atomic Extension Spec**: Zaamo/Zalrsc 指令语义
