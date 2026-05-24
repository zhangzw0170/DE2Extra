-- adapt_exp3.vhd — Exp3 (7-seg display) adapter
-- exp3_top outputs: HEX(55:0), LEDR(17:0), LEDG(8:0) — directly compatible
library ieee;
use ieee.std_logic_1164.all;
use work.de2extra_pkg.all;

entity adapt_exp3 is
    port (
        clk_50  : in  std_logic;
        rst_n   : in  std_logic;
        sw      : in  std_logic_vector(17 downto 0);
        key_n   : in  std_logic_vector(3 downto 0);
        exp_out : out exp_out_t
    );
end entity adapt_exp3;

architecture rtl of adapt_exp3 is
    signal exp3_key_n : std_logic_vector(3 downto 0);
begin
    -- ExpDemo keeps physical KEY0 as board reset.
    -- digital_clock sub-mode remap:
    --   KEY1 -> reset, KEY2 -> write minute, KEY3 -> write hour, second write disabled
    exp3_key_n(3) <= key_n(1);
    exp3_key_n(2) <= key_n(3);
    exp3_key_n(1) <= key_n(2);
    exp3_key_n(0) <= '1';

    u_exp3 : entity work.exp3_top
        port map (
            CLOCK_50 => clk_50,
            SW       => sw,
            KEY_N    => exp3_key_n,
            HEX      => exp_out.hex,
            LEDR     => exp_out.ledr,
            LEDG     => exp_out.ledg
        );

    exp_out.lcd_data <= (others => '0');
    exp_out.lcd_rs   <= '0';
    exp_out.lcd_rw   <= '0';
    exp_out.lcd_en   <= '0';
end architecture rtl;
