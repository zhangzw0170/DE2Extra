-- adapt_exp8.vhd — Exp8 (PS/2 keyboard) adapter
-- Note: PS2 is routed from top-level, not from exp_out
library ieee;
use ieee.std_logic_1164.all;
use work.de2extra_pkg.all;

entity adapt_exp8 is
    port (
        clk_50  : in  std_logic;
        rst_n   : in  std_logic;
        sw      : in  std_logic_vector(17 downto 0);
        key_n   : in  std_logic_vector(3 downto 0);
        ps2_clk : in  std_logic;
        ps2_dat : in  std_logic;
        exp_out : out exp_out_t
    );
end entity adapt_exp8;

architecture rtl of adapt_exp8 is
begin
    u_ps2 : entity work.exp8_ps2_keyboard
        port map (
            CLOCK_50 => clk_50,
            PS2_CLK  => ps2_clk,
            PS2_DAT  => ps2_dat,
            HEX0     => exp_out.hex(6 downto 0),
            HEX1     => exp_out.hex(13 downto 7),
            HEX2     => exp_out.hex(20 downto 14),
            HEX3     => exp_out.hex(27 downto 21),
            HEX4     => exp_out.hex(34 downto 28),
            HEX5     => exp_out.hex(41 downto 35),
            HEX6     => exp_out.hex(48 downto 42),
            HEX7     => exp_out.hex(55 downto 49)
        );

    exp_out.ledr <= (others => '0');
    exp_out.ledg <= (others => '0');
    exp_out.lcd_data <= (others => '0');
    exp_out.lcd_rs   <= '0';
    exp_out.lcd_rw   <= '0';
    exp_out.lcd_en   <= '0';
end architecture rtl;
