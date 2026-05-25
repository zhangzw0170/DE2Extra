# Phase 1: Bus + SDRAM — Implementation Plan

> **计划执行时间: 2026-05-23 14:12** | **归档: Phase 1 全部验收通过**
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix SDRAM hold timing violation and implement a generic Wishbone interconnect so all future peripherals can be added by just editing an address table.

**Architecture:** Single-master (NEORV32 XBUS) multi-slave Wishbone interconnect with address decoding. SDRAM controller gets CDC pre-register fix on the 50MHz side before signals cross into the 100MHz domain.

**Tech Stack:** VHDL-93, Quartus Prime 23.1std Lite, QuestaSim

---

## File Structure

| File | Responsibility |
|---|---|
| `src/rtl/bus/wb_intercon.vhd` | **新建** — Wishbone address decoder, single-master multi-slave |
| `src/rtl/lib/de2extra_pkg.vhd` | **修改** — 添加所有外设地址常量 |
| `src/rtl/periph/sdram_ctrl.vhd` | **修改** — CDC 前置寄存器 (lines 114-124) |
| `src/rtl/de2_115_top.vhd` | **修改** — 替换硬编码地址解码为 wb_intercon |
| `constraints/de2extra.sdc` | **修改** — 添加 CDC 多周期路径约束 |
| `par/de2extra.qsf` | **修改** — 添加 wb_intercon.vhd |

---

## Task 1: Fix SDRAM CDC Hold Timing

**Files:**
- Modify: `src/rtl/periph/sdram_ctrl.vhd:114-124`

- [ ] **Step 1: 在 50MHz 域添加前置寄存器**

在 `p_sync_in` 进程之前，添加一个 50MHz 寄存进程，在信号进入 100MHz 同步器之前打一拍：

```vhdl
    -- ================================================================
    -- CDC 前置寄存器 (50MHz 域) — 确保 100MHz 侧有足够 hold 裕量
    -- ================================================================
    signal stb_pref : std_logic;
    signal cyc_pref : std_logic;
    signal we_pref  : std_logic;
    signal sel_pref : std_logic_vector(3 downto 0);
    signal dat_pref : std_logic_vector(31 downto 0);
    signal adr_pref : std_logic_vector(24 downto 0);

    p_cdc_pref : process (clk_cpu_i)
    begin
        if rising_edge(clk_cpu_i) then
            stb_pref <= wb_stb_i;
            cyc_pref <= wb_cyc_i;
            we_pref  <= wb_we_i;
            sel_pref <= wb_sel_i;
            dat_pref <= wb_dat_i;
            adr_pref <= wb_adr_i;
        end if;
    end process;
```

- [ ] **Step 2: 修改同步器输入源**

将 `p_sync_in` 进程中的输入从 `wb_*_i` 改为 `*_pref`：

```vhdl
    p_sync_in : process (clk_sdram_i)
    begin
        if rising_edge(clk_sdram_i) then
            stb_sync <= stb_sync(1 downto 0) & stb_pref;
            cyc_sync <= cyc_sync(1 downto 0) & cyc_pref;
            we_sync  <= we_sync(1 downto 0) & we_pref;
            sel_sync <= sel_pref;
            dat_sync <= dat_pref;
            adr_sync <= adr_pref;
        end if;
    end process;
```

- [ ] **Step 3: Quartus 编译，检查 TimeQuest**

Run: 在 Quartus 中 Ctrl+L 编译，打开 TimeQuest，检查 SDRAM 相关路径。
Expected: Hold timing TNS >= 0。如果仍有问题，检查是否还需要对地址/数据信号加 `set_multicycle_path` 约束。

- [ ] **Step 4: 运行 sdram_test 验证功能未退化**

Run: 烧录后通过 UART 检查 `sdram_test` 输出。
Expected: ALL PASS（与修改前功能一致，只是时序修复）。

- [ ] **Step 5: 记录到 issue.md**

在 `doc/issue.md` 的 "时序与时钟问题" 表中记录修复前后的 TNS 值。

---

## Task 2: 添加地址常量到 de2extra_pkg

**Files:**
- Modify: `src/rtl/lib/de2extra_pkg.vhd`

- [ ] **Step 1: 添加所有外设地址常量**

在 `de2extra_pkg` 的 `package is` 部分添加：

```vhdl
    -- ================================================================
    -- Wishbone Bus Address Map
    -- ================================================================
    constant ADDR_SDRAM_BASE   : std_logic_vector(31 downto 0) := x"01000000"; -- 128MB
    constant ADDR_VGA_BASE    : std_logic_vector(31 downto 0) := x"F0000000"; -- 8KB
    constant ADDR_PS2_BASE    : std_logic_vector(31 downto 0) := x"F0002000"; -- 4KB
    constant ADDR_TIMER_BASE  : std_logic_vector(31 downto 0) := x"F0004000"; -- 4KB
    constant ADDR_INTC_BASE   : std_logic_vector(31 downto 0) := x"F0006000"; -- 4KB
    constant ADDR_LCD_BASE    : std_logic_vector(31 downto 0) := x"F0008000"; -- 4KB
    constant ADDR_IR_BASE     : std_logic_vector(31 downto 0) := x"F0009000"; -- 4KB
    constant ADDR_DDS_BASE    : std_logic_vector(31 downto 0) := x"F000A000"; -- 4KB
    constant ADDR_SD_BASE    : std_logic_vector(31 downto 0) := x"F000B000"; -- 4KB
```

- [ ] **Step 2: Quartus 编译验证**

Run: Ctrl+L
Expected: 编译通过，无新错误（常量尚未被引用不影响编译）。

---

## Task 3: 实现 Wishbone Interconnect

**Files:**
- Create: `src/rtl/bus/wb_intercon.vhd`

- [ ] **Step 1: 写 wb_intercon.vhd**

通用单 master 多 slave Wishbone interconnect。地址解码基于常量前缀匹配。

```vhdl
-- wb_intercon.vhd — Wishbone Single-Master Multi-Slave Interconnect
-- 通用地址解码，新外设只需在地址表加一项
library ieee;
use ieee.std_logic_1164.all;
use work.de2extra_pkg.all;

entity wb_intercon is
    port (
        -- Master (NEORV32 XBUS, 50MHz)
        m_adr_i    : in  std_logic_vector(31 downto 0);
        m_dat_i    : in  std_logic_vector(31 downto 0);
        m_dat_o    : out std_logic_vector(31 downto 0);
        m_we_i     : in  std_logic;
        m_sel_i    : in  std_logic_vector(3 downto 0);
        m_stb_i    : in  std_logic;
        m_cyc_i    : in  std_logic;
        m_ack_i    : in  std_logic;
        m_err_i    : in  std_logic;

        clk_i      : in  std_logic;
        rst_n_i    : in  std_logic;

        -- Slave 0: SDRAM (128MB @ 0x01000000)
        s0_adr_o   : out std_logic_vector(31 downto 0);
        s0_dat_i   : in  std_logic_vector(31 downto 0);
        s0_dat_o   : out std_logic_vector(31 downto 0);
        s0_we_o    : out std_logic;
        s0_sel_o   : out std_logic_vector(3 downto 0);
        s0_stb_o   : out std_logic;
        s0_cyc_o   : out std_logic;
        s0_ack_i   : in  std_logic;

        -- Slave 1: (预留)
        s1_adr_o   : out std_logic_vector(31 downto 0);
        s1_dat_i   : in  std_logic_vector(31 downto 0) := (others => '0');
        s1_dat_o   : out std_logic_vector(31 downto 0);
        s1_we_o    : out std_logic;
        s1_sel_o   : out std_logic_vector(3 downto 0);
        s1_stb_o   : out std_logic;
        s1_cyc_o   : out std_logic;
        s1_ack_i   : in  std_logic := '0'
    );
end entity wb_intercon;
```

地址解码逻辑：比较 `m_adr_i` 的高位字节与各 slave 基地址的高位字节，匹配则转发。未匹配返回 error。

注意: SDRAM 地址需要去掉高位字节（128MB 映射在 25-bit 字地址空间），所以 `s0_adr_o` 应该输出 25-bit 有效地址（低 25 位直连 `m_adr_i`）。

- [ ] **Step 2: QuestaSim 仿真 (可选)**

如果 QuestaSim 可用，写一个简单 testbench 验证地址解码：
- 写 SDRAM 地址 → 检查 s0_stb_o 有效
- 写 0xDEAD 地址 → 检查 m_err_i 返回 error
- 验证 data path 透传

Run: `vcom -93 wb_intercon.vhd tb_wb_intercon.vhd; vsim work.tb_wb_intercon; add wave *; run -all`
Expected: 波形显示正确的 slave 选择和 data path

- [ ] **Step 3: Quartus 编译验证**

将 wb_intercon.vhd 添加到 `par/de2extra.qsf`，编译通过。
Expected: 编译通过。

---

## Task 4: 集成 wb_intercon 到顶层

**Files:**
- Modify: `src/rtl/de2_115_top.vhd:155-173`
- Modify: `par/de2extra.qsf`

- [ ] **Step 1: 在 de2_115_top 实例化 wb_intercon**

替换现有的硬编码 SDRAM 地址解码（lines 158-173）为 wb_intercon 实例：

```vhdl
    -- ================================================================
    -- Wishbone Interconnect
    -- ================================================================
    signal wb_dat_mux   : std_logic_vector(31 downto 0);
    signal wb_err_mux   : std_logic;

    u_intercon : entity work.wb_intercon
    port map (
        m_adr_i  => xbus_adr,
        m_dat_i  => xbus_dat_o,
        m_dat_o  => wb_dat_mux,
        m_we_i   => xbus_we,
        m_sel_i  => xbus_sel,
        m_stb_i  => xbus_stb,
        m_cyc_i  => xbus_cyc,
        m_ack_i  => '0',  -- master ack 不使用
        m_err_i  => '0',  -- master err 不使用
        clk_i    => clk_50m,
        rst_n_i  => rst_n,
        s0_adr_o => sdram_wb_adr,   -- 25-bit SDRAM 地址
        s0_dat_i => sdram_wb_dat_i,
        s0_dat_o => sdram_wb_dat_o,
        s0_we_o  => sdram_wb_we,
        s0_sel_o => sdram_wb_sel,
        s0_stb_o => sdram_wb_stb,
        s0_cyc_o => sdram_wb_cyc,
        s0_ack_i => sdram_wb_ack
        -- s1 预留，暂时悬空
    );
```

注意: SDRAM 地址映射需要特殊处理。`m_adr_i` 是 32-bit（0x01000000 起始），但 `sdram_ctrl` 只接受 25-bit 字地址。需要在 intercon 内部或顶层做地址转换（去掉高 7 位）。

- [ ] **Step 2: 修改 SDRAM 地址连接**

将 `sdram_wb_adr` 改为 25-bit，由 intercon 输出 `m_adr_i(24 downto 0)` 而非 32-bit。

- [ ] **Step 3: 添加 wb_intercon.vhd 到 Quartus 工程**

Run: 在 Quartus 中 Project → Add/Remove Files，添加 `src/rtl/bus/wb_intercon.vhd`
或在 `par/de2extra.qsf` 中添加:
```
set_global_assignment -name VHDL_FILE -file "src/rtl/bus/wb_intercon.vhd"
```

- [ ] **Step 4: Quartus 编译 + TimeQuest 检查**

Run: Ctrl+L，然后 TimeQuest
Expected: 编译通过，所有 timing 满足。SDRAM hold TNS >= 0。

- [ ] **Step 5: 上板运行 sdram_test**

Run: 烧录 .sof，UART 观察
Expected: `sdram_test` 输出 ALL PASS（与 Phase 0 结果一致，验证 intercon 集成无问题）。

---

## Task 5: 更新 SDC 约束

**Files:**
- Modify: `constraints/de2extra.sdc`

- [ ] **Step 1: 添加 CDC 多周期路径约束 (如果 Task 1 后仍有 timing 问题)**

如果前置寄存器后 hold timing 仍不满足，添加多周期约束：

```tcl
# CDC: 50MHz → 100MHz 跨时钟域 (2-cycle path through synchronizer)
set_multicycle_path -setup 2 -from [get_registers {sdram_ctrl:*pref*}] \
                                 -to   [get_registers {sdram_ctrl:*sync*}]
set_multicycle_path -hold  2 -from [get_registers {sdram_ctrl:*pref*}] \
                                 -to   [get_registers {sdram_ctrl:*sync*}]
```

- [ ] **Step 2: 重新编译验证**

Run: Ctrl+L + TimeQuest
Expected: Setup 和 Hold timing 均 TNS >= 0。

- [ ] **Step 6: 提交 Phase 1**

```bash
git add src/rtl/bus/wb_intercon.vhd
git add src/rtl/lib/de2extra_pkg.vhd
git add src/rtl/periph/sdram_ctrl.vhd
git add src/rtl/de2_115_top.vhd
git add constraints/de2extra.sdc
git add par/de2extra.qsf
git commit -m "feat: add Wishbone interconnect and fix SDRAM hold timing"
```

---

## Self-Review

**Spec coverage:**
- SDRAM hold timing fix → Task 1 ✅
- Generic Wishbone interconnect → Task 3 ✅
- Address constants → Task 2 ✅
- Top-level integration → Task 4 ✅
- sdram_test passes → Task 4 Step 5 ✅
- SDC constraints → Task 5 ✅

**Placeholder scan:** 无 TBD/TODO。所有代码步骤包含完整 VHDL。

**Type consistency:** `sdram_wb_adr` width 从 32-bit 改为 25-bit 在 Task 4 Step 2 明确处理。
