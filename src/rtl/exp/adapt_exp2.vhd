-- adapt_exp2.vhd — Exp2 (LED patterns) adapter
-- Rewritten for LEDR[17:0] while preserving the original HEX wording:
--   SW0=0      -> "OFF"
--   SW0=1,m0   -> "CLr"
--   SW0=1,m1-8 -> "LFx"
library ieee;
use ieee.std_logic_1164.all;
use work.de2extra_pkg.all;

entity adapt_exp2 is
    port (
        clk_50     : in  std_logic;
        rst_n      : in  std_logic;
        selected_i : in  std_logic;
        sw         : in  std_logic_vector(17 downto 0);
        key_n      : in  std_logic_vector(3 downto 0);
        exp_out    : out exp_out_t
    );
end entity adapt_exp2;

architecture rtl of adapt_exp2 is
    constant SEG_L : std_logic_vector(6 downto 0) := "1000111";
    constant SEG_R : std_logic_vector(6 downto 0) := "0101111";
    signal selected_d  : std_logic := '0';
    signal entry_hold  : integer range 0 to 50000 := 50000;
    signal local_rst_n : std_logic;
    signal mode_cur    : std_logic_vector(3 downto 0) := (others => '0');
    signal led_pattern : std_logic_vector(17 downto 0) := (others => '0');
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

    u_led : entity work.led_patterns
        port map (
            clk_i       => clk_50,
            rst_n_i     => local_rst_n,
            en_i        => sw(0),
            mode_next_i => not key_n(1),
            mode_o      => mode_cur,
            led_o       => led_pattern
        );

    exp_out.ledg <= (others => '0');
    exp_out.ledr <= led_pattern;
    exp_out.hex(20 downto 14) <= hex_to_seg7(x"0") when sw(0) = '0' else
                                 hex_to_seg7(x"C") when mode_cur = x"0" else
                                 SEG_L;
    exp_out.hex(13 downto 7)  <= hex_to_seg7(x"F") when sw(0) = '0' else
                                 SEG_L           when mode_cur = x"0" else
                                 hex_to_seg7(x"F");
    exp_out.hex(6 downto 0)   <= hex_to_seg7(x"F") when sw(0) = '0' else
                                 SEG_R           when mode_cur = x"0" else
                                 hex_to_seg7(mode_cur);
    exp_out.hex(55 downto 49) <= (others => '1');  -- HEX7 off
    exp_out.hex(48 downto 42) <= (others => '1');  -- HEX6 off
    exp_out.hex(41 downto 35) <= (others => '1');  -- HEX5 off
    exp_out.hex(34 downto 28) <= (others => '1');  -- HEX4 off
    exp_out.hex(27 downto 21) <= (others => '1');  -- HEX3 off
    exp_out.lcd_data <= (others => '0');
    exp_out.lcd_rs   <= '0';
    exp_out.lcd_rw   <= '0';
    exp_out.lcd_en   <= '0';
end architecture rtl;
