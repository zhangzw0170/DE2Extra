-- adapt_exp1.vhd — Exp1 (3-8 Decoder) adapter for expdemo
library ieee;
use ieee.std_logic_1164.all;
use work.de2extra_pkg.all;

entity adapt_exp1 is
    port (
        clk_50  : in  std_logic;
        rst_n   : in  std_logic;
        sw      : in  std_logic_vector(17 downto 0);
        key_n   : in  std_logic_vector(3 downto 0);
        exp_out : out exp_out_t
    );
end entity adapt_exp1;

architecture rtl of adapt_exp1 is
    signal y : std_logic_vector(7 downto 0);
begin
    -- Exp1: 3-8 decoder (pure combinational, no clock needed)
    u_deco138 : entity work.deco138_for
        port map (
            A   => sw(0),
            B   => sw(1),
            C   => sw(2),
            G1  => sw(5),
            G2A => sw(3),
            G2B => sw(4),
            Y   => y
        );

    -- Map to unified output
    exp_out.hex  <= (others => '1');                -- HEX off
    exp_out.ledr(7 downto 0) <= y;                 -- decoded output (active-low)
    exp_out.ledr(17 downto 8) <= (others => '0');   -- unused LEDR off
    exp_out.ledg <= (others => '0');
    exp_out.lcd_data <= (others => '0');
    exp_out.lcd_rs   <= '0';
    exp_out.lcd_rw   <= '0';
    exp_out.lcd_en   <= '0';
end architecture rtl;
