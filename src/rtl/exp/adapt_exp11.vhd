-- adapt_exp11.vhd — Exp11 (DDS) adapter
-- Match the original lab semantics:
--   SW17 selects slow LED view vs fast SignalTap mode
--   SW7:0 is the DDS frequency word
--   LEDR[11:0] shows the amplitude sample
library ieee;
use ieee.std_logic_1164.all;
use work.de2extra_pkg.all;

entity adapt_exp11 is
    port (
        clk_50  : in  std_logic;
        rst_n   : in  std_logic;
        sw      : in  std_logic_vector(17 downto 0);
        key_n   : in  std_logic_vector(3 downto 0);
        exp_out : out exp_out_t
    );
end entity adapt_exp11;

architecture rtl of adapt_exp11 is
    signal dout : std_logic_vector(9 downto 0);
begin
    u_dds : entity work.DDS
        port map (
            fword => sw(7 downto 0),
            clk   => clk_50,
            rst   => key_n(1),
            mode  => sw(17),
            dout  => dout
        );

    exp_out.ledr <= (17 downto 10 => '0') & dout;
    exp_out.ledg <= (others => '0');
    exp_out.hex  <= (others => '1');  -- all HEX off
    exp_out.lcd_data <= (others => '0');
    exp_out.lcd_rs   <= '0';
    exp_out.lcd_rw   <= '0';
    exp_out.lcd_en   <= '0';
end architecture rtl;
