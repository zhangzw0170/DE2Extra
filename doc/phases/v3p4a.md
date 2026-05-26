# V3 Phase 4a: Conway + PONG 硬件引擎集成

## 1. 概述

本阶段将已完成的 Conway's Game of Life 硬件引擎和 PONG 硬件引擎从 stub 状态升级为实际可用状态。两个引擎的 VHDL 设计和 C 驱动均已完成，当前在 `de2os_top.vhd` 中以立即应答 + 零数据的方式占位。本阶段的工作是：将 VHDL 文件加入 Quartus 工程替换 stub，连通 Wishbone 总线和 VGA 输出，验证编译通过，并确认 C 驱动在 `de2shell_rtos` 中可正常编译。

### 引擎功能摘要

| 引擎 | 文件 | 地址 | 功能 | VGA 输出 |
|------|------|------|------|----------|
| Conway | `conway_engine.vhd` | `0xF0012000` | 80x25 B3/S23 生命游戏，双缓冲 BRAM，LFSR 随机，逐时钟计算 | 无（CPU 读 grid row 写入 VGA 终端） |
| PONG | `pong_engine.vhd` | `0xF0011000` | 640x480 自含 VGA 时序生成器，8x8 球 + 8x40 挡板，硬件物理引擎 | 自含 25MHz VGA 直接驱动 |

## 2. 当前状态

### 已完成

- `src/rtl/periph/conway_engine.vhd` — VHDL 完整，entity 声明如下：
  - 端口：`clk_i`, `rst_n_i` + Wishbone 从站 (`wb_adr_i[4:0]`, `wb_dat_i/o[31:0]`, `wb_we_i`, `wb_stb_i`, `wb_ack_o`)
  - 寄存器：cmd (0x00), control (0x04), status (0x08), population (0x0C), grid_row (0x10)
  - 内部：双缓冲 grid_a/grid_b（各 2000 bit, `M9K` attribute），逐时钟 FSM 计算代数

- `src/rtl/periph/pong_engine.vhd` — VHDL 完整，entity 声明如下：
  - 端口：`clk_50m_i`, `rst_n_i` + Wishbone 从站 + VGA 输出 (`vga_r/g/b_o[7:0]`, `vga_hs/vs_o`, `vga_blank/sync/clk_o`, `vga_en_o`)
  - 寄存器：paddle_l (0x00), paddle_r (0x04), control (0x08), scores (0x0C)
  - 内部：25MHz 像素时钟分频器（从 50MHz），自含 VGA 时序发生器，硬件物理引擎

- `sw/app/de2shell/conway_hw.c` — Conway C 驱动，读 grid row 写入 VGA 文本终端显示
- `sw/app/de2shell/pong_hw.c` — PONG C 驱动，PS/2/UART 双通道挡板控制，score 读取
- `sw/app/de2shell_rtos/makefile` 第 51-52 行已引用 `conway_hw.c` 和 `pong_hw.c`
- `src/rtl/bus/wb_intercon.vhd` — s9/s10 端口已定义，片选 `cs_pong`/`cs_conway` 已实现
- `src/rtl/de2os_top.vhd` — s9/s10 信号已声明并连接到 `wb_intercon`；VGA MUX 已实现三级优先级（PONG > pixel > text）；**第 743-757 行为 stub 赋值**

### 需要完成

1. `par/de2os/de2os.qsf` — 添加 `conway_engine.vhd` 和 `pong_engine.vhd`
2. `de2os_top.vhd` — 删除第 743-757 行的 stub 赋值，替换为真实组件实例化
3. `wb_intercon.vhd` — 已完成，无需修改（s9/s10 端口和片选逻辑已就绪）
4. 仿真验证 — 需编写或确认 Conway/PONG 仿真测试
5. C 驱动编译 — 已在 makefile 中，需确认 `make local` 通过

## 3. 实现步骤

### 步骤 1: QSF 添加 VHDL 文件

在 `par/de2os/de2os.qsf` 中，紧接 `vga_pixel_ctrl.vhd` 之后（第 52 行之后），添加：

```qsf
set_global_assignment -name VHDL_FILE ../../src/rtl/periph/conway_engine.vhd
set_global_assignment -name VHDL_FILE ../../src/rtl/periph/pong_engine.vhd
```

### 步骤 2: de2os_top.vhd 替换 stub

删除第 743-757 行的全部 stub 赋值代码（`pong_wb_dat_i <= ...` 至 `conway_wb_ack <= ...`），替换为两个组件实例化。

#### PONG 引擎实例化

```vhdl
-- PONG engine (s9: 0xF0011000)
u_pong : entity work.pong_engine
port map (
    clk_50m_i   => clk_50m,
    rst_n_i     => rst_n,
    wb_adr_i    => pong_wb_adr,
    wb_dat_i    => pong_wb_dat_o,
    wb_dat_o    => pong_wb_dat_i,
    wb_we_i     => pong_wb_we,
    wb_stb_i    => pong_wb_stb,
    wb_ack_o    => pong_wb_ack,
    vga_r_o     => pong_vga_r,
    vga_g_o     => pong_vga_g,
    vga_b_o     => pong_vga_b,
    vga_hs_o    => pong_vga_hs,
    vga_vs_o    => pong_vga_vs,
    vga_blank_o => pong_vga_blank,
    vga_sync_o  => pong_vga_sync,
    vga_clk_o   => pong_vga_clk,
    vga_en_o    => pong_vga_en
);
```

#### Conway 引擎实例化

```vhdl
-- Conway engine (s10: 0xF0012000)
u_conway : entity work.conway_engine
port map (
    clk_i       => clk_50m,
    rst_n_i     => rst_n,
    wb_adr_i    => conway_wb_adr,
    wb_dat_i    => conway_wb_dat_o,
    wb_dat_o    => conway_wb_dat_i,
    wb_we_i     => conway_wb_we,
    wb_stb_i    => conway_wb_stb,
    wb_ack_o    => conway_wb_ack
);
```

**注意事项**：
- Conway 引擎没有 VGA 输出端口，只通过 Wishbone 提供 grid 数据给 CPU。CPU 驱动 (`conway_hw.c`) 读取 80-bit row 数据后写入 VGA 文本终端显示。
- PONG 引擎的 `vga_en_o` 信号已在 VGA MUX 中用作最高优先级选择（第 558-581 行），当 `pong_vga_en = '1'` 时所有 VGA 信号切换到 PONG 引擎输出。
- 时钟均使用 `clk_50m`（PONG 内部自含 25MHz 分频），复位均使用 `rst_n`。

### 步骤 3: wb_intercon 验证

`wb_intercon.vhd` 中 s9/s10 的连接已完整：

- 端口：s9（PONG）和 s10（Conway）各有 `adr_o[4:0]`, `dat_i[31:0]`, `dat_o[31:0]`, `we_o`, `stb_o`, `ack_i`
- 片选：
  - `cs_pong`：`ADDR_PONG_BASE` (0xF0011000) 至 `ADDR_PONG_BASE + 0x1000`
  - `cs_conway`：`ADDR_CONWAY_BASE` (0xF0012000) 至 `ADDR_CONWAY_BASE + 0x1000`
- 地址映射：`s9_adr_o <= m_adr_i(6 downto 2)`，`s10_adr_o <= m_adr_i(6 downto 2)`，提供 5-bit 字地址（覆盖 0x00-0x1C 寄存器范围）
- 应答和数据回传：在 `m_dat_o <= s9_dat_i` / `m_dat_o <= s10_dat_i` 以及 `m_ack_o <= s9_ack_i` / `m_ack_o <= s10_ack_i` 中正确处理

**结论**：wb_intercon.vhd 无需修改。

### 步骤 4: VGA MUX 优先级确认

`de2os_top.vhd` 第 558-581 行已实现三级 VGA MUX：

```
优先级 1（最高）: PONG 引擎 (pong_vga_en = '1')
优先级 2:         像素模式 (vga_pixel_mode = '1')
优先级 3（最低）: VGA 文本终端 (vga_r_int 等)
```

PONG 引擎的 `vga_en_o` 输出由控制寄存器 bit2（enable）控制。C 驱动中：
- 初始化时写 `PONG_CTL_ENABLE | PONG_CTL_PAUSE` 启用 PONG 并暂停
- 退出时写 `0x00` 关闭 PONG，VGA 输出自动回落到文本终端或像素模式

**结论**：VGA MUX 逻辑已完整，无需修改。

### 步骤 5: 仿真验证策略

#### Conway 引擎仿真

测试文件：`src/rtl/periph/conway_engine_tb.vhd`（需新建）

测试场景：
1. **复位后状态**：读取 status 寄存器确认 busy=0, auto_run=0, generation=0
2. **随机化**：写入 cmd 寄存器 bit1 + seed，等待 busy 清零，读取 grid_row 确认非全零
3. **单步演进**：写入 cmd bit2，等待 busy 清零，读取 generation 确认递增到 1
4. **连续步进**：连续写入 5 次 step，确认 generation=5
5. **清零**：写入 cmd bit0，读取 grid_row 确认全零
6. **auto_run**：写入 cmd bit3 启动，观察 generation 持续递增

验证方法：QuestaSim 波形观察 `gen_state` FSM 状态转换、`grid_a`/`grid_b` 缓冲切换、`generation` 递增。

#### PONG 引擎仿真

测试文件：`src/rtl/periph/pong_engine_tb.vhd`（需新建）

测试场景：
1. **复位后状态**：读取 scores 确认 0:0，VGA 输出 blank/sync 有效
2. **挡板写入**：写入 paddle_l=200, paddle_r=300，读回确认
3. **发球**：写入 control bit0 (serve)，观察 ball 位置开始变化
4. **暂停**：写入 control bit1 (pause)，观察 ball 位置冻结
5. **VGA 时序**：检查 `vga_hs_o`, `vga_vs_o` 波形符合 640x480@60Hz
6. **enable 控制**：确认 `vga_en_o` 跟随 control 寄存器 bit2

验证方法：QuestaSim 波形观察 25MHz `clk_25m` 分频正确性、VGA 时序参数、ball 位置更新。

### 步骤 6: C 驱动编译验证

`sw/app/de2shell_rtos/makefile` 第 51-52 行已包含：

```makefile
APP_SRC += $(DE2SHELL_DIR)/conway_hw.c
APP_SRC += $(DE2SHELL_DIR)/pong_hw.c
```

验证步骤：
1. 确认 `conway_hw.c` 中 `#include "board_status.h"` 和 `#include "vga_hal.h"` 在 de2shell_rtos 搜索路径中可用
2. 确认 `pong_hw.c` 中 `#include "ps2_decoder.h"` 可用
3. 执行 `make local`（主机 GCC + SDL2 编译），确认无编译错误
4. 执行完整交叉编译 `make clean all image NEORV32_HOME=../../../neorv32`（需要 Docker），确认 RISC-V 目标编译通过

**注意事项**：
- `pong_hw.c` 中 `PS2_MMIO_BASE` 定义为 `0xF0008000u`，与 `de2extra_pkg.vhd` 中 `ADDR_PS2_BASE = 0xF0008000` 一致，无需修改。
- `conway_hw.c` 中地址 `0xF0012000u` 与 `de2extra_pkg.vhd` 中 `ADDR_CONWAY_BASE = 0xF0012000` 一致，无需修改。
- `pong_hw.c` 中地址 `0xF0011000u` 与 `de2extra_pkg.vhd` 中 `ADDR_PONG_BASE = 0xF0011000` 一致，无需修改。

### 步骤 7: 资源评估

| 资源 | Conway 引擎 | PONG 引擎 | 合计增量 |
|------|-------------|-----------|----------|
| M9K (BRAM) | 2x2000bit grid + 1x 寄存器 (约 1 M9K) | 无 BRAM（全部寄存器/组合逻辑） | ~1-2 M9K |
| LE (逻辑单元) | FSM + 邻居计数 + WB 从站 (~300 LE) | VGA 时序 + 物理 + 渲染 + WB 从站 (~600 LE) | ~900 LE |
| 时钟域 | 50MHz (clk_50m) | 50MHz + 内部 25MHz 分频 | 无额外 PLL |

Cyclone IV E EP4CE115F29C7 总资源：112K LE + 4Mbit M9K。增量占比很小，不构成布线压力。

## 4. 风险与注意事项

1. **PS/2 地址已正确**：`pong_hw.c` 中 `PS2_MMIO_BASE` 定义为 `0xF0008000u`，与 `de2extra_pkg.vhd` 中 `ADDR_PS2_BASE = 0xF0008000` 一致，无需修改。
2. **PONG VGA 时钟**：PONG 引擎使用内部 50MHz 翻转产生 25MHz 像素时钟，不是精确的 25.175MHz。实际 PONG 输出频率为 25.0MHz，与 640x480 标称 25.175MHz 有 0.7% 偏差。大多数显示器/ADC 容忍此偏差，但若 VGA 显示不稳定需改为 PLL 产生精确 25.175MHz。
3. **Conway 无自含 VGA**：Conway 引擎不直接驱动 VGA，CPU 需逐行读取 80-bit grid 数据（两次 32-bit 读 + 一次 16-bit 有效位）并写入 VGA 终端。在高代数频率时可能造成 CPU 负担较重。
4. **VGA MUX 切换时序**：从 PONG 退回到文本终端时，VGA_CLK 从 25MHz 切换回文本终端时钟。需确认切换瞬间不会导致显示闪烁或 ADC 失锁。建议在 C 驱动中在 disable PONG 后等待至少一帧时间再恢复文本终端输出。

## 验收表

| 编号 | 验收项 | 状态 |
|------|--------|------|
| V3P4A.S1.1 | QSF 添加 conway_engine.vhd 和 pong_engine.vhd，Quartus 编译零错误零警告（除 NEORV32 内部警告外） | ⬜ 未加入 QSF |
| V3P4A.S1.2 | de2os_top.vhd 删除 stub 赋值，替换为 pong_engine + conway_engine 真实实例化，端口映射正确 | ⬜ 仍为 stub (de2os_top.vhd L769-782) |
| V3P4A.S2.1 | Conway 仿真：复位后 status=0，randomize 后 grid_row 非零，step 后 generation=1，clear 后 grid 全零 | ⬜ |
| V3P4A.S2.2 | PONG 仿真：VGA 时序参数正确 (H_ACTIVE=640, V_ACTIVE=480)，发球后 ball 位置变化，scores 寄存器可读 | ⬜ |
| V3P4A.S3.1 | wb_intercon s9/s10 片选和地址映射已确认正确（无需代码修改） | ⬜ |
| V3P4A.S3.2 | VGA MUX 三级优先级已确认：PONG (vga_en) > pixel mode > text terminal | ⬜ |
| V3P4A.S4.1 | pong_hw.c 中 PS2_MMIO_BASE 与 de2extra_pkg.vhd 一致 (0xF0008000) | ⬜ |
| V3P4A.S4.2 | C 驱动 make local 编译通过（de2shell_rtos 交叉编译通过） | 代码已加入 makefile (L50-51) |
| V3P4A.S6.1 | conway_hw.c 在 de2shell_rtos CLI 中注册为可调用命令 | ⬜ 已编译未注册 |
| V3P4A.S6.2 | pong_hw.c 在 de2shell_rtos CLI 中注册为可调用命令 | ⬜ 已编译未注册 |
| V3P4A.S5.1 | Quartus 编译报告：LE/M9K 增量在预期范围内（LE <1000, M9K <3） | ⬜ |
| V3P4A.S5.2 | 时序分析：50MHz 和 25MHz (PONG 内部分频) 路径无负 slack | ⬜ |
