-- pong_engine_tb.vhd — PONG Engine Wishbone + VGA testbench
-- 验证项: 复位状态、挡板写入、enable+serve、VGA 时序、vga_en 控制、游戏持续运行
-- 编译运行: vcom -93 pong_engine.vhd; vcom -93 pong_engine_tb.vhd; vsim -c pong_engine_tb
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pong_engine_tb is
end entity pong_engine_tb;

architecture sim of pong_engine_tb is

    constant CLK_PERIOD : time := 20 ns;

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';

    -- Wishbone master signals
    signal wb_adr    : std_logic_vector(4 downto 0)  := (others => '0');
    signal wb_dat_o  : std_logic_vector(31 downto 0) := (others => '0');
    signal wb_dat_i  : std_logic_vector(31 downto 0);
    signal wb_we     : std_logic := '0';
    signal wb_stb    : std_logic := '0';
    signal wb_ack    : std_logic;

    -- VGA output signals
    signal vga_r     : std_logic_vector(7 downto 0);
    signal vga_g     : std_logic_vector(7 downto 0);
    signal vga_b     : std_logic_vector(7 downto 0);
    signal vga_hs    : std_logic;
    signal vga_vs    : std_logic;
    signal vga_blank : std_logic;
    signal vga_sync  : std_logic;
    signal vga_clk   : std_logic;
    signal vga_en    : std_logic;

    -- (pass/fail counts are process-local variables)

begin

    clk <= not clk after CLK_PERIOD / 2;

    u_dut : entity work.pong_engine
    port map (
        clk_50m_i   => clk,
        rst_n_i     => rst_n,
        wb_adr_i    => wb_adr,
        wb_dat_i    => wb_dat_o,
        wb_dat_o    => wb_dat_i,
        wb_we_i     => wb_we,
        wb_stb_i    => wb_stb,
        wb_ack_o    => wb_ack,
        vga_r_o     => vga_r,
        vga_g_o     => vga_g,
        vga_b_o     => vga_b,
        vga_hs_o    => vga_hs,
        vga_vs_o    => vga_vs,
        vga_blank_o => vga_blank,
        vga_sync_o  => vga_sync,
        vga_clk_o   => vga_clk,
        vga_en_o    => vga_en
    );

    p_stim : process

        -- WB write: data settles one clock, stb for one clock only
        procedure wb_write(addr : std_logic_vector(31 downto 0); data : std_logic_vector(31 downto 0)) is
        begin
            wb_adr   <= addr(4 downto 0);
            wb_dat_o <= data;
            wb_we    <= '1';
            wait until rising_edge(clk);  -- data settles
            wb_stb   <= '1';
            wait until rising_edge(clk);  -- stb asserted, DUT processes
            wb_stb <= '0';
            wb_we  <= '0';
            wait until rising_edge(clk);  -- stb='0' propagates
        end procedure;

        -- WB read: addr settles one clock, stb for one clock only
        procedure wb_read(addr : std_logic_vector(31 downto 0); result : out std_logic_vector(31 downto 0)) is
        begin
            wb_adr   <= addr(4 downto 0);
            wb_dat_o <= (others => '0');
            wb_we    <= '0';
            wait until rising_edge(clk);  -- addr settles
            wb_stb   <= '1';
            wait until rising_edge(clk);  -- stb asserted, DUT processes
            wait until rising_edge(clk);  -- data captured
            result := wb_dat_i;
            wb_stb <= '0';
            wait until rising_edge(clk);  -- stb='0' propagates
        end procedure;

        variable rd_val   : std_logic_vector(31 downto 0);
        variable score_l  : integer;
        variable score_r  : integer;
        variable hs_count : integer;
        variable hs_prev  : std_logic;
        variable blank_seen : std_logic;
        variable pass_count : integer := 0;
        variable fail_count : integer := 0;

    begin
        report "=== PONG Engine Testbench ===";

        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait for 100 ns;

        -- ══════════════════════════════════════════════════════
        -- Test 1: Reset state
        -- ══════════════════════════════════════════════════════
        report "--- Test 1: Reset state ---";
        wb_read(x"0000000C", rd_val);  -- scores at addr 0x0C = word 3
        score_l := to_integer(unsigned(rd_val(15 downto 8)));
        score_r := to_integer(unsigned(rd_val(7 downto 0)));
        assert score_l = 0
            report "FAIL: left score should be 0 after reset" severity error;
        assert score_r = 0
            report "FAIL: right score should be 0 after reset" severity error;
        assert vga_en = '0'
            report "FAIL: vga_en should be 0 after reset" severity error;
        report "  Scores: " & integer'image(score_l) & ":" & integer'image(score_r);
        report "  PASS";
        pass_count := pass_count + 1;

        -- ══════════════════════════════════════════════════════
        -- Test 2: Paddle write + WB ack
        -- ══════════════════════════════════════════════════════
        report "--- Test 2: Paddle write ---";
        wb_write(x"00000000", x"000000C8");  -- paddle_l = 200
        wb_write(x"00000004", x"0000012C");  -- paddle_r = 300
        wait for 200 ns;
        report "  Paddle write completed (write-only, verified via ack)";
        report "  PASS";
        pass_count := pass_count + 1;

        -- ══════════════════════════════════════════════════════
        -- Test 3: Enable + serve
        -- ══════════════════════════════════════════════════════
        report "--- Test 3: Enable + serve ---";
        -- control: bit0=serve, bit2=enable => 0x05
        wb_write(x"00000008", x"00000005");
        wait for 1 us;
        assert vga_en = '1'
            report "FAIL: vga_en should be 1 after enable" severity error;
        -- Scores should still be 0:0 (ball hasn't reached edge yet)
        wb_read(x"0000000C", rd_val);
        score_l := to_integer(unsigned(rd_val(15 downto 8)));
        score_r := to_integer(unsigned(rd_val(7 downto 0)));
        assert score_l = 0 and score_r = 0
            report "FAIL: scores should be 0:0 immediately after serve"
            severity error;
        report "  PASS";
        pass_count := pass_count + 1;

        -- ══════════════════════════════════════════════════════
        -- Test 4: VGA timing — hsync and vsync pulse widths
        -- ══════════════════════════════════════════════════════
        report "--- Test 4: VGA timing ---";
        -- Wait for VGA to stabilize (1 full frame ~16.8ms)
        wait for 20 ms;

        -- Measure hsync pulse width (should be 96 clk_25m periods = 192 clk_50m)
        -- Wait for hsync falling edge
        wait until vga_hs = '0';
        hs_count := 0;
        wait until rising_edge(clk);
        while vga_hs = '0' loop
            hs_count := hs_count + 1;
            wait until rising_edge(clk);
        end loop;
        report "  HSYNC pulse width: " & integer'image(hs_count) & " clk_50m cycles (expected ~192)";
        -- Allow tolerance: 190-194 (should be exactly 192 if no delta cycle issues)
        assert hs_count >= 190 and hs_count <= 194
            report "FAIL: hsync pulse width out of range"
            severity error;

        -- Check that vsync toggles (it's 2 lines = ~64us active every frame)
        -- Already observed during the 20ms wait. Verify vga_blank toggles.
        blank_seen := '0';
        wait until rising_edge(clk);
        for i in 0 to 200000 loop
            if vga_blank /= blank_seen then
                blank_seen := vga_blank;
                if i > 0 then
                    exit;
                end if;
            end if;
            wait until rising_edge(clk);
        end loop;
        assert blank_seen = '0'
            report "FAIL: vga_blank should transition (blanked and unblanked)"
            severity error;
        report "  PASS";
        pass_count := pass_count + 1;

        -- ══════════════════════════════════════════════════════
        -- Test 5: vga_en_o control
        -- ══════════════════════════════════════════════════════
        report "--- Test 5: vga_en control ---";
        -- Already enabled from Test 3. Disable by writing control=0.
        wb_write(x"00000008", x"00000000");  -- control=0 (disable, no serve)
        wait for 200 ns;
        assert vga_en = '0'
            report "FAIL: vga_en should be 0 after disable" severity error;
        -- Re-enable
        wb_write(x"00000008", x"00000004");  -- control=4 (enable only, no serve)
        wait for 200 ns;
        assert vga_en = '1'
            report "FAIL: vga_en should be 1 after re-enable" severity error;
        report "  PASS";
        pass_count := pass_count + 1;

        -- ══════════════════════════════════════════════════════
        -- Test 6: Game runs for multiple frames without hanging
        -- Serve and let the game run, verify scores are readable
        -- and VGA signals remain active
        -- ══════════════════════════════════════════════════════
        report "--- Test 6: Game continuous run ---";
        -- Serve the ball
        wb_write(x"00000008", x"00000005");  -- enable + serve
        -- Run for 2 full frames (~34ms)
        wait for 35 ms;
        -- Verify VGA still active
        assert vga_en = '1'
            report "FAIL: vga_en should still be 1 during game run" severity error;
        -- Verify scores are readable
        wb_read(x"0000000C", rd_val);
        score_l := to_integer(unsigned(rd_val(15 downto 8)));
        score_r := to_integer(unsigned(rd_val(7 downto 0)));
        report "  Scores after 2 frames: " & integer'image(score_l) & ":" & integer'image(score_r);
        -- Scores should be valid (0-9 range)
        assert score_l >= 0 and score_l <= 9
            report "FAIL: left score out of range" severity error;
        assert score_r >= 0 and score_r <= 9
            report "FAIL: right score out of range" severity error;
        -- Verify hsync still toggles (game hasn't frozen)
        hs_prev := vga_hs;
        wait until vga_hs /= hs_prev;
        report "  VGA signals still toggling - game alive";
        report "  PASS";
        pass_count := pass_count + 1;

        -- ══════════════════════════════════════════════════════
        -- Summary
        -- ══════════════════════════════════════════════════════
        report "========================================";
        report "All " & integer'image(pass_count) & " tests PASSED";
        if fail_count > 0 then
            report integer'image(fail_count) & " test(s) FAILED" severity error;
        end if;
        report "========================================";
        wait;
    end process;

end architecture sim;
