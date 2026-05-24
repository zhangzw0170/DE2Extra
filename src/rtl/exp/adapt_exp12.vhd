-- adapt_exp12.vhd — Exp12 (Simple CPU) adapter
-- simple_cpu outputs: LEDR(17:0), LEDG(7:0), HEX0-7, LCD signals
library ieee;
use ieee.std_logic_1164.all;
use work.de2extra_pkg.all;

entity adapt_exp12 is
    port (
        clk_50     : in  std_logic;
        rst_n      : in  std_logic;
        selected_i : in  std_logic;
        sw         : in  std_logic_vector(17 downto 0);
        key_n      : in  std_logic_vector(3 downto 0);
        exp_out    : out exp_out_t;
        pc_o       : out std_logic_vector(7 downto 0);
        ac_o       : out std_logic_vector(15 downto 0);
        ir_o       : out std_logic_vector(15 downto 0);
        step_o     : out std_logic_vector(7 downto 0);
        auto_o     : out std_logic;
        detail_o   : out std_logic;
        fsm_o      : out std_logic_vector(3 downto 0)
    );
end entity adapt_exp12;

architecture rtl of adapt_exp12 is
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

    local_rst_n <= '0' when (rst_n = '0') or (entry_hold > 0) else key_n(1);

    u_cpu : entity work.simple_cpu
        generic map (
            CLK_DIV_BITS => 22
        )
        port map (
            CLOCK_50 => clk_50,
            KEY0_N   => local_rst_n,
            KEY1_N   => key_n(2),
            KEY2_N   => key_n(3),
            SW16     => sw(16),
            LEDR     => exp_out.ledr,
            LEDG     => exp_out.ledg(7 downto 0),
            HEX0     => exp_out.hex(6 downto 0),
            HEX1     => exp_out.hex(13 downto 7),
            HEX2     => exp_out.hex(20 downto 14),
            HEX3     => exp_out.hex(27 downto 21),
            HEX4     => exp_out.hex(34 downto 28),
            HEX5     => exp_out.hex(41 downto 35),
            HEX6     => exp_out.hex(48 downto 42),
            HEX7     => exp_out.hex(55 downto 49),
            LCD_DATA => exp_out.lcd_data,
            LCD_RS   => exp_out.lcd_rs,
            LCD_RW   => exp_out.lcd_rw,
            LCD_EN   => exp_out.lcd_en,
            LCD_ON   => open,
            LCD_BLON => open,
            PC_O     => pc_o,
            AC_O     => ac_o,
            IR_O     => ir_o,
            STEP_CNT_O => step_o,
            AUTO_RUN_O => auto_o,
            DETAIL_O   => detail_o,
            FSM_ID_O   => fsm_o
        );

    exp_out.ledg(8) <= '0';
end architecture rtl;
