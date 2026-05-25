# V3P4C: NTT 加速器上板验证

> 日期: 2026-05-25 | 状态: ⬜ 待接入 de2shell_rtos
> 前置: ntt_sdf.vhd 已编译, Python 验证全 PASS, C 驱动已就绪

---

## 1. 概述

NTT (Number Theoretic Transform) 加速器是 ML-KEM/ML-DSA 等后量子密码标准的核心运算。本项目采用 DIF Cooley-Tukey SDF 架构, N=256, q=3329, g=17。

当前状态: VHDL 代码完成且编译通过, C 驱动 (SW reference + HW MMIO 双模式) 完成, Python 验证脚本全部 PASS。剩余工作仅为将 ntt.c 接入 de2shell_rtos 固件并上板验证正确性与加速比。

---

## 2. 当前状态

| 组件 | 文件 | 状态 |
|------|------|------|
| VHDL 加速器 | `src/rtl/periph/ntt_sdf.vhd` | ☑ 编译通过 (de2os 8,125 LEs) |
| Wishbone 集成 | `src/rtl/bus/wb_intercon.vhd` s4 | ☑ 地址解码 @ 0xF000F000 |
| Python 验证 | `ntt_verify.py` | ☑ round-trip / delta / convolution / vs naive 全 PASS |
| C 驱动 (SW) | `sw/app/de2shell/ntt.c` LOCAL_BUILD 模式 | ☑ Barrett reduction + DIF stages 7->0 |
| C 驱动 (HW) | `sw/app/de2shell/ntt.c` NEORV32 模式 | ☑ MMIO: write 256 words, start, poll, readback |
| C 头文件 | `sw/app/de2shell/ntt.h` | ☑ 寄存器定义 + inline 函数 |
| rtos makefile | `sw/app/de2shell_rtos/makefile` | ⬜ 未包含 ntt.c |
| rtos CLI 注册 | `sw/app/de2shell_rtos/main.c` | ⬜ 未注册 prog_ntt |
| 上板验证 | — | ⬜ 未开始 |

### 已知注意项

- `ntt.h` 中 `NTT_BASE` 定义为 `0xF000F000u`, 与 `de2extra_pkg.vhd` 中 `ADDR_NTT_BASE` 一致
- CLAUDE.md 和 de2extra_pkg.vhd 中 NTT 地址均为 `0xF000F000`, IR 地址为 `0xF000C000`, 地址已统一
- HW 模式下 `cmd_ntt()` 引用 `ntt_a[]` 数组, 但该数组仅在 `LOCAL_BUILD` 下声明 -- NEORV32 构建时需补充临时缓冲区或重构为就地操作
- `ntt.c` 中 `cmd_roundtrip()` 的 NEORV32 分支直接读写 HW 寄存器 (不经过软件缓冲区), 需确认与 `cmd_ntt()` 的数据流一致

---

## 3. 实现步骤

### 3.1 接入 de2shell_rtos makefile

在 `sw/app/de2shell_rtos/makefile` 的 de2shell programs 区段添加:

```makefile
APP_SRC += $(DE2SHELL_DIR)/ntt.c
```

### 3.2 注册 CLI 命令

在 `sw/app/de2shell_rtos/main.c` 中:

1. 添加 `extern const program_t prog_ntt;`
2. 在 `prog_id_t` 枚举中添加 `PROG_NTT`
3. 在程序指针表中添加 `[PROG_NTT] = &prog_ntt`
4. 在 CLI 命令注册表中添加 `"ntt"` 对应 `PROG_NTT`
5. 在 `active_prog_stack_words()` 中为 `PROG_NTT` 分配合适的栈大小 (建议 512 words, 含 256 个 uint16_t 临时缓冲)

### 3.3 修复 NEORV32 构建问题

当前 `ntt.c` 的 NEORV32 分支存在以下问题需修复:

- `cmd_ntt()` 使用 `ntt_a[]` 数组, 但该数组仅在 `#ifdef LOCAL_BUILD` 下声明
- 需要在 NEORV32 构建路径中也提供临时缓冲区 (256 x uint16_t = 512 bytes)
- 或重构 `cmd_ntt()` 使其在 HW 模式下直接操作寄存器, 不依赖中间缓冲

建议方案: 在 `#ifndef LOCAL_BUILD` 下也声明 `ntt_a[]` 数组 (放在 main.c 的 SDRAM 堆上, 或改为 static 局部变量)。

### 3.4 上板测试用例

#### T1: NTT 正确性 (delta 测试)

```
ntt
  load delta
  ntt
  dump
```

预期: NTT([1,0,...,0]) 应输出全 1 (DFT of delta = 常数序列)。实际输出为 bit-reversed 全 1, `dump` 显示前 32 个应为 0001。

#### T2: INTT 正确性

```
ntt
  load delta
  ntt
  intt
  dump
```

预期: INTT(NTT(x)) == x (取模 3329)。由于 bit-reversal 两次抵消, 应恢复为 [1, 0, ..., 0]。

#### T3: Round-trip 测试

```
ntt
  load delta
  roundtrip
```

预期: 输出 `ROUND-TRIP PASS`。

#### T4: 卷积测试 (可选)

需编写 C 端测试: 生成随机 a[], b[], 计算 NTT(a) * NTT(b), INTT 结果应等于循环卷积 a * b mod q。

#### T5: 性能测量

利用 `NTT_REG_CYCLES` 寄存器 (偏移 0x408) 读取 HW NTT 周期数。同时用 NEORV32 CLINT mtime 测量 SW 参考实现 (LOCAL_BUILD) 的 NTT 耗时, 计算加速比。

预期: HW NTT 应在数千周期内完成 (SDF 流水线), SW 参考约需数十万周期。加速比目标 > 100x。

---

## 4. 验收表

| 编号 | 验收项 | 状态 |
|------|--------|------|
| V3P4C.S1.1 | makefile 添加 ntt.c, de2shell_rtos 固件编译通过 (无链接错误) | ⬜ |
| V3P4C.S1.2 | `ntt` CLI 命令注册成功, shell 中输入 `ntt` 进入交互界面 | ⬜ |
| V3P4C.S1.3 | NTT delta 测试: `load delta` -> `ntt` -> `dump` 输出全 1 | ⬜ |
| V3P4C.S1.4 | INTT 正确性: `load delta` -> `ntt` -> `intt` -> `dump` 恢复原始数据 | ⬜ |
| V3P4C.S1.5 | Round-trip 测试: `roundtrip` 输出 PASS | ⬜ |
| V3P4C.S1.6 | 加速比测量: HW NTT vs SW 参考, 加速比 > 100x (利用 CYCLES 寄存器) | ⬜ |
| V3P4C.S1.7 | NEORV32 构建无编译/链接警告 | ⬜ |
| V3P4C.S1.8 | Conway/PONG 等其他程序在 NTT 接入后仍正常运行 (无地址冲突) | ⬜ |

---

## 5. 参考资料

| 文件 | 说明 |
|------|------|
| `src/rtl/periph/ntt_sdf.vhd` | VHDL 加速器 (DIF Cooley-Tukey, SDF, N=256) |
| `sw/app/de2shell/ntt.c` | C 驱动 (SW reference + HW MMIO) |
| `sw/app/de2shell/ntt.h` | 寄存器定义 + 接口 |
| `src/rtl/lib/de2extra_pkg.vhd` | `ADDR_NTT_BASE = 0xF000F000` |
| `src/rtl/bus/wb_intercon.vhd` | s4 端口, cs_ntt 地址解码 |
| `doc/phases/phase5-sdram-gui.md` section 9 | NTT 加速器完整规格 |
