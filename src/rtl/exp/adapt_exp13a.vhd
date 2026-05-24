-- adapt_exp13a.vhd — Exp13a (LCD SOC) adapter
-- lcd_soc outputs: LCD_DATA, LCD_RS, LCD_RW, LCD_EN, LCD_ON, LCD_BLON, HEX(6:0)
library ieee;
use ieee.std_logic_1164.all;
use work.de2extra_pkg.all;

entity adapt_exp13a is
    port (
        clk_50     : in  std_logic;
        rst_n      : in  std_logic;
        selected_i : in  std_logic;
        sw         : in  std_logic_vector(17 downto 0);
        key_n      : in  std_logic_vector(3 downto 0);
        exp_out    : out exp_out_t;
        msg_sel_o  : out std_logic_vector(1 downto 0);
        scroll_o   : out std_logic_vector(5 downto 0)
    );
end entity adapt_exp13a;

architecture rtl of adapt_exp13a is
    signal selected_d : std_logic := '0';
    signal entry_hold : integer range 0 to 50000 := 50000;
    signal local_rst_n : std_logic;
begin
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            if rst_n = '0' then
                selected_d <= '0';
                entry_hold <= 50000;
            else
                selected_d <= selected_i;
                if (selected_i = '1') and (selected_d = '0') then
                    entry_hold <= 50000;
                elsif entry_hold > 0 then
                    entry_hold <= entry_hold - 1;
                end if;
            end if;
        end if;
    end process;

    local_rst_n <= '0' when (rst_n = '0') or (entry_hold > 0) else '1';

    u_lcd : entity work.lcd_soc
        port map (
            CLOCK_50 => clk_50,
            RST_N    => local_rst_n,
            KEY0_N   => key_n(1),
            SW       => sw(7 downto 0),
            LCD_DATA => exp_out.lcd_data,
            LCD_RS   => exp_out.lcd_rs,
            LCD_RW   => exp_out.lcd_rw,
            LCD_EN   => exp_out.lcd_en,
            LCD_ON   => open,
            LCD_BLON => open,
            HEX      => exp_out.hex(6 downto 0),
            MSG_SEL_O => msg_sel_o,
            SCROLL_O  => scroll_o
        );

    exp_out.ledr <= (others => '0');
    exp_out.ledg <= (others => '0');
    exp_out.hex(55 downto 49) <= (others => '1');  -- HEX7 off
    exp_out.hex(48 downto 42) <= (others => '1');  -- HEX6 off
    exp_out.hex(41 downto 35) <= (others => '1');  -- HEX5 off
    exp_out.hex(34 downto 28) <= (others => '1');  -- HEX4 off
    exp_out.hex(27 downto 21) <= (others => '1');  -- HEX3 off
    exp_out.hex(20 downto 14) <= (others => '1');  -- HEX2 off
    exp_out.hex(13 downto 7)  <= (others => '1');  -- HEX1 off
end architecture rtl;
