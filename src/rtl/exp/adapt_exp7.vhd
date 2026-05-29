-- adapt_exp7.vhd — Exp7: VGA animated test patterns
--
-- SW[2:0] selects pattern mode (same as Exp6)
-- SW[6:4] = animation speed (1..15 pixels/frame, 0=1)
-- SW[17]  = animation enable
-- KEY1 = reset
-- HEX7:6 = frame count
-- HEX5:4 = animation shift (hex)
-- HEX3:2 = V count high bits
-- HEX1:0 = H count high bits
-- LEDR[17:0] = shift register (shows animation progress)
-- LEDG8 = frame tick
-- LEDG[7:0] = V counter low bits
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.de2extra_pkg.all;

entity adapt_exp7 is
    port (
        clk_50  : in  std_logic;
        rst_n   : in  std_logic;
        sw      : in  std_logic_vector(17 downto 0);
        key_n   : in  std_logic_vector(3 downto 0);
        exp_out : out exp_out_t;
        vga_r     : out std_logic_vector(7 downto 0);
        vga_g     : out std_logic_vector(7 downto 0);
        vga_b     : out std_logic_vector(7 downto 0);
        vga_hs    : out std_logic;
        vga_vs    : out std_logic;
        vga_clk   : out std_logic;
        vga_blank : out std_logic;
        vga_sync  : out std_logic
    );
end entity adapt_exp7;

architecture rtl of adapt_exp7 is
    signal hc        : std_logic_vector(9 downto 0);
    signal vc        : std_logic_vector(9 downto 0);
    signal frame     : std_logic;
    signal frame_cnt : unsigned(15 downto 0);
    signal key1_prev : std_logic;
    signal key1_fall : std_logic;
    signal anim_spd  : std_logic_vector(3 downto 0);
begin

    -- KEY1 falling-edge detector
    p_key : process(clk_50, rst_n)
    begin
        if rst_n = '0' then
            key1_prev <= '1';
        elsif rising_edge(clk_50) then
            key1_prev <= key_n(1);
        end if;
    end process;
    key1_fall <= '1' when key1_prev = '1' and key_n(1) = '0' else '0';

    -- Speed: SW[6:4] × 2 (avoid speed=0)
    anim_spd <= x"2" when sw(6 downto 4) = "000" else
                std_logic_vector(unsigned("0" & sw(6 downto 4)) & "0");

    -- Frame counter
    p_cnt : process(clk_50, rst_n)
    begin
        if rst_n = '0' then
            frame_cnt <= (others => '0');
        elsif rising_edge(clk_50) then
            if key1_fall = '1' then
                frame_cnt <= (others => '0');
            elsif frame = '1' then
                frame_cnt <= frame_cnt + 1;
            end if;
        end if;
    end process;

    -- VGA test pattern with animation
    u_vga : entity work.vga_test_pattern
        port map (
            clk_50m_i   => clk_50,
            rst_n_i     => rst_n,
            mode_i      => sw(2 downto 0),
            animate_i   => sw(17),
            speed_i     => anim_spd,
            vga_r_o     => vga_r,
            vga_g_o     => vga_g,
            vga_b_o     => vga_b,
            vga_hs_o    => vga_hs,
            vga_vs_o    => vga_vs,
            vga_clk_o   => vga_clk,
            vga_blank_o => vga_blank,
            vga_sync_o  => vga_sync,
            hc_o        => hc,
            vc_o        => vc,
            frame_o     => frame
        );

    -- HEX debug
    exp_out.hex(55 downto 49) <= hex_to_seg7(std_logic_vector(frame_cnt(7 downto 4)));
    exp_out.hex(48 downto 42) <= hex_to_seg7(std_logic_vector(frame_cnt(3 downto 0)));
    exp_out.hex(41 downto 35) <= hex_to_seg7("0" & sw(2 downto 0));
    exp_out.hex(34 downto 28) <= hex_to_seg7(std_logic_vector(vc(9 downto 6)));
    exp_out.hex(27 downto 21) <= hex_to_seg7(std_logic_vector(vc(5 downto 2)));
    exp_out.hex(20 downto 14) <= hex_to_seg7(std_logic_vector(hc(9 downto 6)));
    exp_out.hex(13 downto 7)  <= hex_to_seg7(std_logic_vector(hc(5 downto 2)));
    exp_out.hex(6 downto 0)   <= hex_to_seg7("0" & sw(6 downto 4));

    -- LEDR[9:0] = H counter low, LEDR[17:10] = anim speed display
    exp_out.ledr(9 downto 0)   <= hc;
    exp_out.ledr(17)           <= sw(17);  -- animate enable
    exp_out.ledr(16 downto 14) <= sw(6 downto 4);  -- speed bits
    exp_out.ledr(13 downto 10) <= (others => '0');

    exp_out.ledg(8)          <= frame;
    exp_out.ledg(7 downto 0) <= vc(7 downto 0);

    exp_out.lcd_data <= (others => '0');
    exp_out.lcd_rs   <= '0';
    exp_out.lcd_rw   <= '0';
    exp_out.lcd_en   <= '0';

end architecture rtl;
