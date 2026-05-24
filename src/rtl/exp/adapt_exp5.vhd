-- adapt_exp5.vhd — Exp5 (FSM) adapter
library ieee;
use ieee.std_logic_1164.all;
use work.de2extra_pkg.all;

entity adapt_exp5 is
    port (
        clk_50  : in  std_logic;
        rst_n   : in  std_logic;
        sw      : in  std_logic_vector(17 downto 0);
        key_n   : in  std_logic_vector(3 downto 0);
        exp_out : out exp_out_t
    );
end entity adapt_exp5;

architecture rtl of adapt_exp5 is
    signal e_ledr0, e_ledr1 : std_logic;
begin
    u_exp5 : entity work.exp5_top
        port map (
            clk     => clk_50,
            reset   => key_n(1),   -- exp5_top reset is active-low
            w       => sw(0),
            fsm_sel => sw(17 downto 16),
            ledg    => exp_out.ledg,
            ledr0   => e_ledr0,
            ledr1   => e_ledr1,
            HEX6    => exp_out.hex(48 downto 42)
        );

    exp_out.ledr(0) <= e_ledr0;
    exp_out.ledr(1) <= e_ledr1;
    exp_out.ledr(17 downto 2) <= (others => '0');
    exp_out.hex(55 downto 49) <= (others => '1');  -- HEX7 off
    exp_out.hex(41 downto 35) <= (others => '1');  -- HEX5 off
    exp_out.hex(34 downto 28) <= (others => '1');  -- HEX4 off
    exp_out.hex(27 downto 21) <= (others => '1');  -- HEX3 off
    exp_out.hex(20 downto 14) <= (others => '1');  -- HEX2 off
    exp_out.hex(13 downto 7)  <= (others => '1');  -- HEX1 off
    exp_out.hex(6 downto 0)   <= (others => '1');  -- HEX0 off
    exp_out.lcd_data <= (others => '0');
    exp_out.lcd_rs   <= '0';
    exp_out.lcd_rw   <= '0';
    exp_out.lcd_en   <= '0';
end architecture rtl;
