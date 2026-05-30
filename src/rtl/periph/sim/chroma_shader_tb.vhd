-- chroma_shader_tb.vhd -- ChromaShader Wishbone + VGA output testbench
-- Tests: reset, enable fill, hash correctness, CELL read, PAINT, force_refresh, VGA output
-- Run (QuestaSim):
--   vcom -2008 ../chroma_dp_ram.vhd
--   vcom -2008 ../chroma_shader.vhd
--   vcom -2008 chroma_shader_tb.vhd
--   vsim -c chroma_shader_tb -do "run -all; quit -f"
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity chroma_shader_tb is
end entity chroma_shader_tb;

architecture sim of chroma_shader_tb is

    constant CLK_PERIOD : time := 20 ns;   -- 50 MHz
    constant CLK25_PERIOD : time := 40 ns; -- 25 MHz

    -- DUT signals
    signal clk      : std_logic := '0';
    signal rst_n    : std_logic := '0';
    signal wb_adr   : std_logic_vector(4 downto 0)  := (others => '0');
    signal wb_wdata : std_logic_vector(31 downto 0) := (others => '0');
    signal wb_rdata : std_logic_vector(31 downto 0);
    signal wb_we    : std_logic := '0';
    signal wb_stb   : std_logic := '0';
    signal wb_ack   : std_logic;

    signal clk_25m  : std_logic := '0';
    signal rd_addr  : integer range 0 to 2399 := 0;
    signal rd_char  : std_logic_vector(7 downto 0);
    signal rd_fg    : std_logic_vector(15 downto 0);
    signal rd_bg    : std_logic_vector(15 downto 0);
    signal chroma_en : std_logic;

    -- Register offsets
    constant R_CTRL     : std_logic_vector(4 downto 0) := "00000"; -- 0x00
    constant R_SEED     : std_logic_vector(4 downto 0) := "00001"; -- 0x04
    constant R_OFF_X    : std_logic_vector(4 downto 0) := "00010"; -- 0x08
    constant R_OFF_Y    : std_logic_vector(4 downto 0) := "00011"; -- 0x0C
    constant R_PLAYER_X : std_logic_vector(4 downto 0) := "00100"; -- 0x10
    constant R_PLAYER_Y : std_logic_vector(4 downto 0) := "00101"; -- 0x14
    constant R_CELL     : std_logic_vector(4 downto 0) := "00110"; -- 0x18
    constant R_PAINT    : std_logic_vector(4 downto 0) := "00111"; -- 0x1C
    constant R_STATUS   : std_logic_vector(4 downto 0) := "01000"; -- 0x20

begin

    clk <= not clk after CLK_PERIOD / 2;
    -- 25 MHz derived from 50 MHz (toggle)
    process(clk)
    begin
        if rising_edge(clk) then
            clk_25m <= not clk_25m;
        end if;
    end process;

    u_dut : entity work.chroma_shader
    port map (
        clk_i       => clk,
        rst_n_i     => rst_n,
        wb_adr_i    => wb_adr,
        wb_dat_i    => wb_wdata,
        wb_dat_o    => wb_rdata,
        wb_we_i     => wb_we,
        wb_stb_i    => wb_stb,
        wb_ack_o    => wb_ack,
        clk_25m_i   => clk_25m,
        rd_addr_i   => rd_addr,
        rd_char_o   => rd_char,
        rd_fg_o     => rd_fg,
        rd_bg_o     => rd_bg,
        chroma_en_o => chroma_en
    );

    p_stim : process
        variable pass_count : integer := 0;
        variable fail_count : integer := 0;
        variable v : std_logic_vector(31 downto 0);

        -- WB write helper
        procedure wb_write(addr : std_logic_vector(4 downto 0);
                           data : std_logic_vector(31 downto 0)) is
        begin
            wb_adr   <= addr;
            wb_wdata <= data;
            wb_we    <= '1';
            wait until rising_edge(clk);
            wb_stb   <= '1';
            wait until rising_edge(clk);
            wb_stb <= '0';
            wb_we  <= '0';
            wait until rising_edge(clk);
        end procedure;

        -- WB read helper
        procedure wb_read(addr : std_logic_vector(4 downto 0);
                          result : out std_logic_vector(31 downto 0)) is
        begin
            wb_adr   <= addr;
            wb_wdata <= (others => '0');
            wb_we    <= '0';
            wait until rising_edge(clk);
            wb_stb   <= '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            result := wb_rdata;
            wb_stb <= '0';
            wait until rising_edge(clk);
        end procedure;

        -- Reference hash function (matches DUT)
        impure function ref_hash(wx : unsigned(15 downto 0);
                                 wy : unsigned(15 downto 0);
                                 sd : unsigned(31 downto 0))
            return unsigned is
            variable h : unsigned(31 downto 0);
        begin
            h := sd xor resize(wx, 32) sll 7 xor resize(wy, 32) sll 20;
            h := h xor (h(18 downto 0) & "0000000000000");
            h := h xor ("00000000000000000" & h(31 downto 17));
            h := h xor (h(26 downto 0) & "00000");
            h := h xor resize(wy, 32) sll 3 xor resize(wx, 32) sll 16;
            h := h xor ("00000000000" & h(31 downto 11));
            h := h xor (h(24 downto 0) & "0000000");
            return h;
        end function;

        -- Determine terrain type from hash[7:0]
        function hash_to_type(h : unsigned(7 downto 0)) return integer is
        begin
            if h < 56 then   return 0;  -- T_DEEP
            elsif h < 76 then return 1;  -- T_SHALLOW
            elsif h < 96 then return 2;  -- T_SAND
            elsif h < 166 then return 3; -- T_GRASS
            elsif h < 196 then return 4; -- T_FOREST
            elsif h < 226 then return 5; -- T_MOUNT
            else              return 6;  -- T_SNOW
            end if;
        end function;

        -- Terrain type to RGB332 color
        function terrain_color(t : integer) return std_logic_vector is
        begin
            case t is
                when 0 => return x"03";
                when 1 => return x"14";
                when 2 => return x"F5";
                when 3 => return x"39";
                when 4 => return x"12";
                when 5 => return x"A2";
                when 6 => return x"FF";
                when others => return x"00";
            end case;
        end function;

        procedure check(cond : boolean; msg : string) is
        begin
            if cond then
                pass_count := pass_count + 1;
            else
                report "FAIL: " & msg severity error;
                fail_count := fail_count + 1;
            end if;
        end procedure;

        variable ref_h : unsigned(31 downto 0);
        variable ref_type : integer;
        variable ref_fg : std_logic_vector(7 downto 0);
        variable has_gold : boolean;
        variable busy_v, ready_v : std_logic;

    begin
        report "=== ChromaShader Testbench ===";

        -- Reset
        rst_n <= '0';
        wait for 200 ns;
        rst_n <= '1';
        wait for 200 ns;

        ----------------------------------------------------------------
        -- Test 1: Reset state
        ----------------------------------------------------------------
        report "--- Test 1: Reset state ---";
        wb_read(R_CTRL, v);
        check(v(0) = '0', "enable should be 0 after reset");
        wb_read(R_STATUS, v);
        check(v(0) = '0', "busy should be 0 after reset");
        check(v(1) = '0', "frame_ready should be 0 after reset");
        check(chroma_en = '0', "chroma_en should be 0 when disabled");
        report "  done";

        ----------------------------------------------------------------
        -- Test 2: Enable triggers auto-fill, wait for frame_ready
        ----------------------------------------------------------------
        report "--- Test 2: Enable + auto-fill ---";
        wb_write(R_SEED, x"CAFE1234");
        wb_write(R_OFF_X, x"00000000");
        wb_write(R_OFF_Y, x"00000000");
        wb_write(R_PLAYER_X, x"00000028");  -- col 40
        wb_write(R_PLAYER_Y, x"0000000C");  -- row 12
        -- Enable (auto-fill triggers on rising edge)
        wb_write(R_CTRL, x"00000001");

        -- Wait for fill FSM to complete (2000 cells * 2 clocks = 4000 * 20ns = 80us)
        -- Poll STATUS until frame_ready
        for i in 1 to 20 loop
            wb_read(R_STATUS, v);
            if v(1) = '1' then
                report "  frame_ready after poll " & integer'image(i);
                exit;
            end if;
            wait for 10 us;
        end loop;
        wb_read(R_STATUS, v);
        check(v(0) = '0', "busy should be 0 after fill");
        check(v(1) = '1', "frame_ready should be 1 after fill");
        report "  done";

        ----------------------------------------------------------------
        -- Test 3: Hash correctness — check CELL at player pos (40,12)
        ----------------------------------------------------------------
        report "--- Test 3: Hash correctness at (40,12) ---";
        -- Player at col=40, row=12, world offset (0,0)
        -- Hash input: wx=40, wy=12, seed=0xCAFE1234
        ref_h := ref_hash(to_unsigned(40, 16), to_unsigned(12, 16), x"CAFE1234");
        ref_type := hash_to_type(ref_h(7 downto 0));
        ref_fg := terrain_color(ref_type);
        has_gold := (ref_h(23 downto 16) = x"5A");

        report "  ref_hash=" & integer'image(to_integer(ref_h(7 downto 0)))
                & " type=" & integer'image(ref_type)
                & " gold=" & boolean'image(has_gold);

        wb_read(R_CELL, v);
        report "  CELL read: type=" & integer'image(to_integer(unsigned(v(2 downto 0))))
               & " gold=" & std_logic'image(v(3))
               & " fg=0x" & integer'image(to_integer(unsigned(v(11 downto 4))))
               & " bg=0x" & integer'image(to_integer(unsigned(v(19 downto 12))));

        check(v(2 downto 0) = std_logic_vector(to_unsigned(ref_type, 3)),
              "terrain type mismatch: got " & integer'image(to_integer(unsigned(v(2 downto 0)))));
        check(v(11 downto 4) = ref_fg,
              "fg color mismatch: got 0x" & integer'image(to_integer(unsigned(v(11 downto 4)))));
        if has_gold then
            check(v(3) = '1', "gold flag should be set");
        else
            check(v(3) = '0', "gold flag should be clear");
        end if;
        report "  done";

        ----------------------------------------------------------------
        -- Test 4: Verify CELL at different position — move player to (0,0)
        ----------------------------------------------------------------
        report "--- Test 4: CELL at (0,0) ---";
        wb_write(R_PLAYER_X, x"00000000");
        wb_write(R_PLAYER_Y, x"00000000");
        wait for 100 ns;

        ref_h := ref_hash(to_unsigned(0, 16), to_unsigned(0, 16), x"CAFE1234");
        ref_type := hash_to_type(ref_h(7 downto 0));
        ref_fg := terrain_color(ref_type);
        has_gold := (ref_h(23 downto 16) = x"5A");

        wb_read(R_CELL, v);
        check(v(2 downto 0) = std_logic_vector(to_unsigned(ref_type, 3)),
              "CELL(0,0) type mismatch");
        check(v(11 downto 4) = ref_fg,
              "CELL(0,0) fg mismatch");
        report "  CELL(0,0): type=" & integer'image(to_integer(unsigned(v(2 downto 0))))
               & " fg=0x" & integer'image(to_integer(unsigned(v(11 downto 4))));
        report "  done";

        ----------------------------------------------------------------
        -- Test 5: VGA output — check chroma_en and char for terrain region
        ----------------------------------------------------------------
        report "--- Test 5: VGA output ---";
        -- Read VGA output at terrain address (row 2, col 0 = addr 160)
        wait until rising_edge(clk_25m);
        rd_addr <= 160;  -- first terrain cell (row 2, col 0)
        wait until rising_edge(clk_25m);
        wait until rising_edge(clk_25m);
        check(chroma_en = '1', "chroma_en should be 1 for terrain addr 160");
        report "  addr=160 char=0x" & integer'image(to_integer(unsigned(rd_char)))
               & " fg=0x" & integer'image(to_integer(unsigned(rd_fg)));

        -- Read VGA output outside terrain (row 0, col 0 = addr 0)
        rd_addr <= 0;
        wait until rising_edge(clk_25m);
        wait until rising_edge(clk_25m);
        check(chroma_en = '0', "chroma_en should be 0 for addr 0 (HUD region)");
        report "  done";

        ----------------------------------------------------------------
        -- Test 6: Player overlay on VGA output
        ----------------------------------------------------------------
        report "--- Test 6: Player overlay ---";
        -- Player is at (0,0) → terrain local addr 0 → terminal addr 160
        rd_addr <= 160;
        wait until rising_edge(clk_25m);
        wait until rising_edge(clk_25m);
        wait until rising_edge(clk_25m);
        check(rd_char = x"40", "player cell should show '@' (0x40), got 0x"
              & integer'image(to_integer(unsigned(rd_char))));
        check(rd_fg = x"FFFF", "player fg should be white");
        report "  done";

        ----------------------------------------------------------------
        -- Test 7: PAINT — write custom cell
        ----------------------------------------------------------------
        report "--- Test 7: PAINT ---";
        -- Move player to (10,5) first, paint grass
        wb_write(R_PLAYER_X, x"0000000A");  -- col 10
        wb_write(R_PLAYER_Y, x"00000005");  -- row 5
        wait for 100 ns;
        -- Paint: type=T_GRASS(3), gold=0, fg=0x39, bg=0x39
        -- PAINT layout: [23:16]=bg, [15:8]=fg, [7]=gold, [2:0]=type
        wb_write(R_PAINT, x"00393903");  -- bg=0x39, fg=0x39, gold=0, type=3
        wait for 100 ns;

        -- Verify via VGA: player at (10,5) → terrain local addr = 5*80+10 = 410 → terminal addr 570
        -- BRAM pipeline: 1 cycle for rd_local register + 1 cycle for BRAM read = 3 edges needed
        rd_addr <= 570;
        wait until rising_edge(clk_25m);
        wait until rising_edge(clk_25m);
        wait until rising_edge(clk_25m);
        -- Player overlay should show '@'
        check(rd_char = x"40", "painted cell+player should show '@'");
        report "  player at painted cell: char=0x" & integer'image(to_integer(unsigned(rd_char)));
        report "  done";

        ----------------------------------------------------------------
        -- Test 8: Move player away from painted cell, check paint shows
        ----------------------------------------------------------------
        report "--- Test 8: Paint without player ---";
        wb_write(R_PLAYER_X, x"0000000B");  -- move to col 11
        wait for 100 ns;

        rd_addr <= 570;  -- back to (10,5)
        wait until rising_edge(clk_25m);
        wait until rising_edge(clk_25m);
        wait until rising_edge(clk_25m);
        -- No player here now, should show paint data (grass '▒' = 0xB1)
        report "  painted cell no player: char=0x" & integer'image(to_integer(unsigned(rd_char)));
        report "  done";

        ----------------------------------------------------------------
        -- Test 9: force_refresh with new offset
        ----------------------------------------------------------------
        report "--- Test 9: force_refresh with offset ---";
        wb_write(R_OFF_X, x"00000005");  -- shift X by 5
        wb_write(R_OFF_Y, x"0000000A");  -- shift Y by 10
        wb_write(R_CTRL, x"00000003");   -- enable + force_refresh

        -- Wait for fill
        for i in 1 to 20 loop
            wb_read(R_STATUS, v);
            if v(1) = '1' then exit; end if;
            wait for 10 us;
        end loop;
        wb_read(R_STATUS, v);
        check(v(1) = '1', "frame_ready after force_refresh");

        -- Check CELL at player (11,5): world coords (16,15)
        wb_write(R_PLAYER_X, x"00000000");
        wb_write(R_PLAYER_Y, x"00000000");
        wait for 100 ns;
        ref_h := ref_hash(to_unsigned(5, 16), to_unsigned(10, 16), x"CAFE1234");
        ref_type := hash_to_type(ref_h(7 downto 0));
        ref_fg := terrain_color(ref_type);

        wb_read(R_CELL, v);
        check(v(2 downto 0) = std_logic_vector(to_unsigned(ref_type, 3)),
              "offset CELL type mismatch after force_refresh");
        report "  CELL(0,0) with offset(5,10): type=" & integer'image(to_integer(unsigned(v(2 downto 0))));
        report "  done";

        ----------------------------------------------------------------
        -- Test 10: Disable clears chroma_en
        ----------------------------------------------------------------
        report "--- Test 10: Disable ---";
        wb_write(R_CTRL, x"00000000");
        wait for 200 ns;
        wait until rising_edge(clk_25m);
        rd_addr <= 160;
        wait until rising_edge(clk_25m);
        wait until rising_edge(clk_25m);
        check(chroma_en = '0', "chroma_en should be 0 after disable");
        report "  done";

        ----------------------------------------------------------------
        -- Summary
        ----------------------------------------------------------------
        report "=== ChromaShader TB Summary: "
               & integer'image(pass_count) & " passed, "
               & integer'image(fail_count) & " failed ===";
        if fail_count = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report "SOME TESTS FAILED" severity error;
        end if;

        wait;
    end process;

end architecture sim;
