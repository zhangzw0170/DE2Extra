# Phase 2b: VGA Terminal + PS/2 + Conway — Implementation Plan

> **计划执行时间: 2026-05-23 14:12** | **归档: VGA 文字终端 + PS/2 已验证上板**
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 80x25 hardware VGA text terminal with PS/2 keyboard input and Conway's Game of Life demo, all in VHDL.

**Architecture:** VGA text terminal reads from dual-port BRAM (80×25 chars, 2 pages). PS/2 controller outputs raw scan codes via FIFO with IRQ. Conway GoL computes cell evolution in hardware using neighbor-counting pipeline. CPU interacts via Wishbone registers.

**Tech Stack:** VHDL-93, Quartus Prime 23.1std Lite, QuestaSim (testbench), 8×16 font ROM (.mif)

---

## File Structure

| File | Responsibility |
|---|---|
| `src/rtl/periph/vga_text_terminal.vhd` | **新建** — VGA 时序生成 + 字符渲染 + 双页缓冲 |
| `src/rtl/periph/font_rom.mif` | **新建** — 8×16 ASCII 字库 ROM 初始化文件 |
| `src/rtl/periph/ps2_keyboard.vhd` | **新建** — PS/2 接收 + scan code FIFO |
| `src/rtl/periph/conway_gol.vhd` | **新建** — Conway 生命游戏硬件引擎 |
| `src/sim/tb_vga_terminal.vhd` | **新建** — VGA + PS/2 testbench |
| `src/sim/tb_conway.vhd` | **新建** — Conway GoL testbench |

---

## Task 1: VGA 时序生成器

**Files:**
- Create: `src/rtl/periph/vga_text_terminal.vhd`

- [ ] **Step 1: 实现 VGA 640×480@60Hz 时序**

VGA 时序参数 (640×480@60Hz):
```
H_VISIBLE=640, H_FRONT=16, H_SYNC=96, H_BACK=48, H_TOTAL=800
V_VISIBLE=480, V_FRONT=10, V_SYNC=2, V_BACK=33, V_TOTAL=525
```

实体端口:
```vhdl
entity vga_text_terminal is
    port (
        -- Clock (25MHz pixel clock)
        clk_25m_i   : in  std_logic;
        -- VGA 输出
        vga_r       : out std_logic_vector(7 downto 0);
        vga_g       : out std_logic_vector(7 downto 0);
        vga_b       : out std_logic_vector(7 downto 0);
        vga_hs      : out std_logic;
        vga_vs      : out std_logic;
        vga_blank   : out std_logic;
        vga_sync    : out std_logic;
        vga_clk     : out std_logic;
        -- Wishbone slave
        wb_clk_i    : in  std_logic;
        wb_adr_i    : in  std_logic_vector(15 downto 0);  -- 偏移地址 (16-bit)
        wb_dat_i    : in  std_logic_vector(15 downto 0);
        wb_dat_o    : out std_logic_vector(15 downto 0);
        wb_we_i     : in  std_logic;
        wb_sel_i    : in  std_logic_vector(1 downto 0);
        wb_stb_i    : in  std_logic;
        wb_cyc_i    : in  std_logic;
        wb_ack_o    : out std_logic;
        -- 控制寄存器
        cursor_x_i  : in  std_logic_vector(6 downto 0);  -- 从 wb 地址映射
        cursor_y_i  : in  std_logic_vector(4 downto 0);
        ctrl_i      : in  std_logic_vector(2 downto 0);  -- [0]=enable,[1]=blink,[2]=page
        bg_color_i  : in  std_logic_vector(15 downto 0);  -- RGB565 背景色
        clear_i     : in  std_logic  -- 写 1 清当前页
    );
end entity;
```

VGA 时序: `h_counter` 0-799, `v_counter` 0-524。在 `h_counter < H_VISIBLE` 且 `v_counter < V_VISIBLE` 时有效像素区。

- [ ] **Step 2: QuestaSim 仿真验证时序**

写 `tb_vga_terminal.vhd`，产生 25MHz 时钟，检查 HS/VS 波形脉宽和周期。
Expected: HS 负脉冲宽度 96×40ns=3.84μs，VS 负脉冲宽度 2×40ns=80ns，总帧周期 525×800×40ns=16.8ms (59.5Hz)。

---

## Task 2: 字符缓冲区和字体 ROM

**Files:**
- Modify: `src/rtl/periph/vga_text_terminal.vhd`
- Create: `src/rtl/periph/font_rom.mif`

- [ ] **Step 1: 实现双页文本缓冲区**

两页缓冲区，每页 80×25 = 2000 words × 16bit = 4000 bytes。
使用 VHDL 数组 + `Ram_style="no_rw_check"` 推断为 BRAM。

地址映射 (Wishbone 偏移):
```
0x0000 - 0x0F9F  Page 0 文本缓冲 (2000 words × 2B = 4000B)
0x1000 - 0x1005  控制寄存器 (cursor_x, cursor_y, ctrl, bg_color, clear)
0x2000 - 0x2F9F  Page 1 文本缓冲 (2000 words × 2B = 4000B)
```

- [ ] **Step 2: 生成 8×16 ASCII 字库 .mif 文件**

使用开源 `cp437_8x16` 字库 (如 [VGA-text-mode-fonts](https://github.com/Vutov/vga-text-mode-fonts) 的 `CP437_8x16.bin`)，写 Python 脚本将 raw binary 转换为 Quartus `.mif` 格式：
- 256 个字符 (0-255)，每字符 8 列 × 16 行 (只使用 0-127 ASCII 子集)
- 每 bit = 1 表示该像素亮（前景色），0 = 暗
- 存储格式: 256×16 words (每行一个 word，bit 7=左像素，bit 0=右像素)，depth=4096, width=8

- [ ] **Step 3: 实现像素渲染管线**

在 VGA 有效像素区：
```
1. 根据 h_counter, v_counter 计算 buffer address = (v_counter * 80) + (h_counter / 8)
2. 从当前活动页 buffer 读取 char_data (16-bit: [7:0]=ASCII, [15:8]=颜色)
3. 用 v_counter 计算字体行偏移 = v_counter mod 16
4. 用 h_counter mod 8 计算字体列
5. 查 font ROM 得到像素 bit
6. 如果 bit=1: 输出前景色; bit=0: 输出背景色
```

- [ ] **Step 4: 仿真验证**

Testbench 写入字符 'A' 到 (0,0)，检查 VGA 输出在正确的像素位置出现 'A' 的 8×16 点阵。
Expected: 波形中可见 'A' 的像素图案。

---

## Task 3: 光标和控制寄存器

**Files:**
- Modify: `src/rtl/periph/vga_text_terminal.vhd`

- [ ] **Step 1: 实现光标闪烁**

光标位置由 `cursor_x_i` 和 `cursor_y_i` 给定（通过 Wishbone 寄存器设置）。
在渲染管线中：如果当前像素 == (cursor_x, cursor_y) 且 `ctrl_i[1]=1`：
- 用 50MHz 时钟（不是 25MHz）做 ~1Hz 闪烁计数器
- 闪烁时反转前景色/背景色

- [ ] **Step 2: 实现清屏**

`clear_i` 上升沿时，将当前活动页的 2000 words 全部写为 0x0020 (空格 + 默认颜色)。

- [ ] **Step 3: 实现页切换**

`ctrl_i[2]` 选择活动页: 0=Page 0, 1=Page 1。
VGA 渲染管线根据此位选择读取哪个 buffer。

---

## Task 4: PS/2 键盘控制器

**Files:**
- Create: `src/rtl/periph/ps2_keyboard.vhd`

- [ ] **Step 1: 实现 PS/2 字节接收**

PS/2 协议: 11-bit 帧 (1 start + 8 data + 1 parity + 1 stop)。
- 在 50MHz 时钟域用计数器做位采样（PS/2 clock ~15kHz，50MHz 下每个 PS2 clock ~3333 个采样点，足够采样）
- 接收到完整字节后推入 16-entry FIFO

```vhdl
entity ps2_keyboard is
    port (
        clk_50m_i   : in  std_logic;
        rst_n_i     : in  std_logic;
        ps2_clk_io   : inout std_logic;  -- PS/2 时钟
        ps2_dat_io   : inout std_logic;  -- PS/2 数据
        -- Wishbone slave
        wb_dat_o    : out std_logic_vector(7 downto 0);  -- scan code (读后清 FIFO)
        wb_stb_i    : in  std_logic;
        wb_cyc_i    : in  std_logic;
        wb_ack_o    : out std_logic;
        -- 中断
        data_ready_o : out std_logic
    );
end entity;
```

- [ ] **Step 2: 实现奇偶校验**

校验位 = XOR of data[7:0] + start bit (0)。校验失败丢弃该字节。

- [ ] **Step 3: Testbench 仿真**

发送已知 scan code 序列，验证 FIFO 输出正确。
Expected: 发送 F0 12 (Q release)，FIFO 输出 0xF0 然后 0x12。

---

## Task 5: Conway 生命游戏引擎

**Files:**
- Create: `src/rtl/periph/conway_gol.vhd`

- [ ] **Step 1: 设计邻居计数器**

对于每个 cell (r, c)，需要计数周围 8 个邻居中 alive 的数量。
优化：展开 8 个方向的读取，用 3-bit 计数器。每行可用移位寄存器快速计算相邻行的邻居。

- [ ] **Step 2: 实现 B3/S23 规则**

```
next_state = (count == 3) OR (alive AND count == 2)
```

- [ ] **Step 3: 双缓冲 + vblank 同步**

使用两块 BRAM 作为 A/B 缓冲。
每 vblank 期间：对当前缓冲区全部计算一次下一代，写入另一个缓冲区，然后交换。
对于 80×25 网格，流水线方式处理：每行 27 个时钟（读邻居 + 计数 + 规则），25 行 = 675 时钟/代。

- [ ] **Step 4: VGA 集成**

Conway 的输出直接映射到 VGA text buffer：
- alive cell → 写 0xDB (█, 块状字符) + 白色
- dead cell → 写 0x20 (空格)

通过 Wishbone 寄存器控制: `life start/pause`, `life glider/gun/random/clear`, `life speed`。

- [ ] **Step 5: 验证滑翔机**

预设滑翔机图案，运行若干代后检查滑翔机位置是否正确移动。
Expected: 滑翔机每 4 代向右下移动 1 格。

---

## Task 6: 顶层集成 (de2_115_top)

**Files:**
- Modify: `src/rtl/de2_115_top.vhd`
- Modify: `src/rtl/glue/clk_rst_gen.vhd` — 添加 25MHz 时钟输出
- Modify: `par/de2extra.qsf` — 添加新 VHDL 文件 + .mif

- [ ] **Step 1: 修改 clk_rst_gen 输出 25MHz**

在 PLL 配置中添加 25MHz 输出（50MHz / 2），或用 D 触发器二分频。

- [ ] **Step 2: 在 de2_115_top 实例化 VGA + PS/2**

添加 VGA, PS/2 端口到 entity。
实例化 `vga_text_terminal` 和 `ps2_keyboard`，通过 wb_intercon 连接。

- [ ] **Step 3: 添加 PS/2 端口**

在顶层添加 `PS2_CLK` 和 `PS2_DAT` 双向端口。

- [ ] **Step 4: 添加所有新文件到 Quartus 工程**

```
set_global_assignment -name VHDL_FILE -file "src/rtl/periph/vga_text_terminal.vhd"
set_global_assignment -name VHDL_FILE -file "src/rtl/periph/ps2_keyboard.vhd"
set_global_assignment -name VHDL_FILE -file "src/rtl/periph/conway_gol.vhd"
```

- [ ] **Step 5: 编译 + 上板验证**

Expected: VGA 显示彩色字符。PS/2 键盘输入字符出现在 VGA 上。Conway 滑翔机正确运行。
记录到 issue.md。

---

## Self-Review

**Spec coverage:**
- VGA 640×480@60Hz → Task 1 ✅
- 80×25 双页缓冲 + 字库 → Task 2 ✅
- 光标闪烁 + 清屏 + 页切换 → Task 3 ✅
- PS/2 字节接收 + FIFO → Task 4 ✅
- Conway B3/S23 + 双缓冲 → Task 5 ✅
- 顶层集成 → Task 6 ✅

**Placeholder scan:**
- Task 2 Step 2: 字库 .mif 生成需要具体实现或引用开源字库。Agentic worker 需要找到并集成一个 8×16 VGA font。

**Type consistency:**
- VGA 时序使用 25MHz (50MHz 二分频)，需确保 clk_rst_gen 输出正确。
- Wishbone 地址宽度: VGA 用 16-bit 偏移地址 (足够寻址 8KB)，PS/2 用 8-bit。
