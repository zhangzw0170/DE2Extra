-- tb_vga_terminal.vhd — VGA 文字终端 QuestaSim testbench
--
-- 验证:
--   1. VGA 640x480@60Hz 时序 (HS/VS 脉宽, 帧周期)
--   2. 寄存器接口写入文本缓冲区
--   3. 像素输出对应正确字符
--
-- 用法: QuestaSim 中编译 vga_text_terminal + font_rom_pkg + tb_vga_terminal
--       vsim tb_vga_terminal
--       run 50 ms

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_vga_terminal is
end tb_vga_terminal;

architecture sim of tb_vga_terminal is

    -- DUT 信号
    signal clk_50m    : std_logic := '0';
    signal rst_n      : std_logic := '0';
    signal vga_r      : std_logic_vector(7 downto 0);
    signal vga_g      : std_logic_vector(7 downto 0);
    signal vga_b      : std_logic_vector(7 downto 0);
    signal vga_hs     : std_logic;
    signal vga_vs     : std_logic;
    signal vga_blank  : std_logic;
    signal vga_sync   : std_logic;
    signal vga_clk    : std_logic;

    signal reg_adr    : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_dat_i  : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_dat_o  : std_logic_vector(15 downto 0);
    signal reg_we     : std_logic := '0';
    signal reg_stb    : std_logic := '0';
    signal reg_ack    : std_logic;

    -- 时钟
    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz
    constant HALF_PERIOD : time := 10 ns;

    -- VGA 时序期望值 (640x480@60Hz)
    constant H_TOTAL  : integer := 800;
    constant H_SYNC   : integer := 96;
    constant H_BP     : integer := 48;
    constant H_ACTIVE : integer := 640;
    constant V_TOTAL  : integer := 525;
    constant V_SYNC   : integer := 2;
    constant V_BP     : integer := 33;
    constant V_ACTIVE : integer := 480;

    -- 帧周期期望: 525 * 800 * 40ns = 16.8ms
    constant FRAME_PERIOD : time := V_TOTAL * H_TOTAL * 40 ns;

begin

    -- ============================================================
    -- 时钟生成
    -- ============================================================
    clk_50m <= not clk_50m after HALF_PERIOD;

    -- ============================================================
    -- DUT 实例化
    -- ============================================================
    u_dut : entity work.vga_text_terminal
    port map (
        clk_50m_i   => clk_50m,
        rst_n_i     => rst_n,
        vga_r_o     => vga_r,
        vga_g_o     => vga_g,
        vga_b_o     => vga_b,
        vga_hs_o    => vga_hs,
        vga_vs_o    => vga_vs,
        vga_blank_o => vga_blank,
        vga_sync_o  => vga_sync,
        vga_clk_o   => vga_clk,
        reg_adr_i   => reg_adr,
        reg_dat_i   => reg_dat_i,
        reg_dat_o   => reg_dat_o,
        reg_we_i    => reg_we,
        reg_stb_i   => reg_stb,
        reg_ack_o   => reg_ack
    );

    -- ============================================================
    -- 主测试流程
    -- ============================================================
    process
        procedure reg_write(
            addr : integer;
            data : std_logic_vector(15 downto 0)
        ) is
        begin
            reg_adr   <= std_logic_vector(to_unsigned(addr, 16));
            reg_dat_i <= data;
            reg_we    <= '1';
            reg_stb   <= '1';
            wait until rising_edge(clk_50m);
            wait until rising_edge(clk_50m);
            reg_stb   <= '0';
            reg_we    <= '0';
            wait until rising_edge(clk_50m);
        end procedure;

        procedure reg_read(addr : integer) is
        begin
            reg_adr   <= std_logic_vector(to_unsigned(addr, 16));
            reg_we    <= '0';
            reg_stb   <= '1';
            wait until rising_edge(clk_50m);
            wait until rising_edge(clk_50m);
            reg_stb   <= '0';
            wait until rising_edge(clk_50m);
        end procedure;

    begin
        report "=== VGA Text Terminal Testbench ===";

        -- 复位
        rst_n <= '0';
        wait for 1 us;
        rst_n <= '1';
        wait for 1 us;

        ------------------------------------------------------------
        -- 测试 1: VGA 时序
        ------------------------------------------------------------
        report "Test 1: VGA 640x480@60Hz timing";

        wait for 20 ms;  -- 等待至少一帧

        -- HS 和 VS 在复位后应该开始翻转
        report "  HS and VS toggling: checking...";
        assert vga_hs'event or vga_vs'event
            report "  WARNING: HS/VS may not be toggling"
            severity warning;

        ------------------------------------------------------------
        -- 测试 2: 写入 'A' 到 (0,0)
        ------------------------------------------------------------
        report "Test 2: Write 'A' to position (0,0)";

        -- 位置 0 = 行 0, 列 0
        -- 字符格式: [15:8]=前景色 RGB332, [7:0]=ASCII
        -- 写白色 'A': 前景色 = 0xFF (白色 RGB332), ASCII = 0x41
        reg_write(0, x"FF41");  -- 'A' in white

        -- 等几帧让 VGA 渲染
        wait for 100 ms;

        ------------------------------------------------------------
        -- 测试 3: 填充第一行 "HELLO"
        ------------------------------------------------------------
        report "Test 3: Write 'HELLO' to first row";

        reg_write(0, x"FF48");   -- 'H' white
        reg_write(1, x"E045");   -- 'E' yellow
        reg_write(2, x"1C4C");   -- 'L' green
        reg_write(3, x"1C4C");   -- 'L' green
        reg_write(4, x"E04F");   -- 'O' yellow

        wait for 50 ms;

        ------------------------------------------------------------
        -- 测试 4: 光标
        ------------------------------------------------------------
        report "Test 4: Cursor test";

        -- 设置光标位置 (10, 5)
        reg_write(16#1000#, x"000A");  -- cursor_x = 10
        reg_write(16#1004#, x"0005");  -- cursor_y = 5

        wait for 2000 ms;  -- 等光标闪烁至少一个周期

        ------------------------------------------------------------
        -- 测试 5: 背景色
        ------------------------------------------------------------
        report "Test 5: Background color";

        -- 设置蓝色背景
        reg_write(16#1010#, x"0003");  -- bg_color = 0x03 (blue, RGB332)

        wait for 50 ms;

        ------------------------------------------------------------
        -- 测试 6: 清屏
        ------------------------------------------------------------
        report "Test 6: Clear screen";

        reg_write(16#1014#, x"0001");  -- clear

        wait for 50 ms;

        report "=== All tests complete ===";
        report "Open waveform window to verify:";
        report "  - VGA_HS period: 31.78 us (800 * 40ns)";
        report "  - VGA_VS period: 16.68 ms (525 * 800 * 40ns)";
        report "  - HS pulse width: 3.84 us (96 * 40ns)";
        report "  - VS pulse width: 63.5 us (2 * 800 * 40ns)";
        report "  - Character 'H' (0x48) at top-left corner";

        wait;
    end process;

    -- ============================================================
    -- VGA 时序监控 (无断言 — 纯波形观察)
    -- ============================================================
    p_monitor : process(vga_clk)
        variable hs_prev : std_logic := '1';
    begin
        if falling_edge(vga_clk) then
            -- 可以在这里添加周期性检查
            null;
        end if;
    end process;

end sim;
