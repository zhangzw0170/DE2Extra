-- adapt_exp9.vhd — Exp9 (UART) adapter
-- Note: UART is routed from top-level, not from exp_out
library ieee;
use ieee.std_logic_1164.all;
use work.de2extra_pkg.all;

entity adapt_exp9 is
    port (
        clk_50  : in  std_logic;
        rst_n   : in  std_logic;
        sw      : in  std_logic_vector(17 downto 0);
        key_n   : in  std_logic_vector(3 downto 0);
        uart_txd : out std_logic;
        uart_rxd : in  std_logic;
        exp_out : out exp_out_t
    );
end entity adapt_exp9;

architecture rtl of adapt_exp9 is
    signal uart_txd_loop : std_logic;
begin
    u_uart : entity work.uart_top
        port map (
            CLOCK_50 => clk_50,
            SW       => sw(7 downto 0),
            KEY0_N   => key_n(1),
            UART_TXD => uart_txd_loop,
            UART_RXD => uart_txd_loop,
            LEDR     => exp_out.ledr(15 downto 0),
            LEDG     => exp_out.ledg(7 downto 0),
            HEX5     => exp_out.hex(41 downto 35),
            HEX4     => exp_out.hex(34 downto 28),
            HEX1     => exp_out.hex(13 downto 7),
            HEX0     => exp_out.hex(6 downto 0)
        );

    -- Keep the shell UART on the physical RS-232 pins. Exp9 loops its own TX
    -- back into RX so the original UART demo still works inside expdemo.
    uart_txd <= '1';

    exp_out.ledr(17 downto 16) <= (others => '0');
    exp_out.ledg(8) <= '0';
    exp_out.hex(55 downto 49) <= (others => '1');  -- HEX7 off
    exp_out.hex(48 downto 42) <= (others => '1');  -- HEX6 off
    exp_out.hex(27 downto 21) <= (others => '1');  -- HEX3 off
    exp_out.hex(20 downto 14) <= (others => '1');  -- HEX2 off
    exp_out.lcd_data <= (others => '0');
    exp_out.lcd_rs   <= '0';
    exp_out.lcd_rw   <= '0';
    exp_out.lcd_en   <= '0';
end architecture rtl;
