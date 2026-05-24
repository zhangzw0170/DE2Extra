-- lcd_wb.vhd -- HD44780 LCD controller with Wishbone register interface
--
-- Register map (word-aligned byte offsets):
--   0x00  DR  write: display character, read: status (bit 0 = busy)
--   0x04  CR  write: HD44780 command (RS=0)
--
-- Software must poll DR read until bit 0 = 0 before writing next.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lcd_wb is
    port (
        clk_i      : in  std_logic;
        rst_n_i    : in  std_logic;
        -- Wishbone slave
        wb_adr_i   : in  std_logic_vector(3 downto 0);
        wb_dat_i   : in  std_logic_vector(31 downto 0);
        wb_dat_o   : out std_logic_vector(31 downto 0);
        wb_we_i    : in  std_logic;
        wb_stb_i   : in  std_logic;
        wb_ack_o   : out std_logic;
        -- HD44780 physical pins
        lcd_data   : out std_logic_vector(7 downto 0);
        lcd_rs     : out std_logic;
        lcd_rw     : out std_logic;
        lcd_en     : out std_logic;
        lcd_on     : out std_logic;
        lcd_blon   : out std_logic
    );
end entity lcd_wb;

architecture rtl of lcd_wb is

    -- HD44780 timing @ 50MHz
    constant EN_PULSE_C   : integer := 25;       -- 500ns enable pulse
    constant DELAY_NORM_C : integer := 2000;     -- ~40us normal command
    constant DELAY_LONG_C : integer := 80000;    -- ~1.6ms clear/home

    type state_t is (S_IDLE, S_PULSE, S_DELAY);
    signal state     : state_t;
    signal delay_cnt : integer range 0 to DELAY_LONG_C;
    signal pend_data : std_logic_vector(7 downto 0);
    signal pend_rs   : std_logic;
    signal busy      : std_logic;
    signal ack_reg   : std_logic;

    signal is_long_cmd : std_logic;

begin

    lcd_on   <= '1';
    lcd_blon <= '1';
    lcd_rw   <= '0';  -- write only

    -- Wishbone ack: single cycle
    process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            ack_reg <= '0';
        elsif rising_edge(clk_i) then
            ack_reg <= wb_stb_i and not ack_reg;
        end if;
    end process;
    wb_ack_o <= ack_reg;

    -- Wishbone read: status register
    process(all)
    begin
        wb_dat_o <= (others => '0');
        if wb_stb_i = '1' and wb_we_i = '0' then
            wb_dat_o(0) <= busy;
        end if;
    end process;

    -- Wishbone write: latch command/data
    process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            pend_data <= (others => '0');
            pend_rs   <= '0';
        elsif rising_edge(clk_i) then
            if wb_stb_i = '1' and wb_we_i = '1' and busy = '0' then
                pend_data <= wb_dat_i(7 downto 0);
                if wb_adr_i(3 downto 2) = "00" then  -- offset 0x00: data
                    pend_rs <= '1';
                else                                    -- offset 0x04: command
                    pend_rs <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Detect clear/home command (0x01 or 0x02) for longer delay
    is_long_cmd <= '1' when pend_rs = '0' and
                   (pend_data = x"01" or pend_data = x"02") else '0';

    -- HD44780 timing state machine
    process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            state     <= S_IDLE;
            busy      <= '0';
            delay_cnt <= 0;
            lcd_data  <= (others => '0');
            lcd_rs    <= '0';
            lcd_en    <= '0';
        elsif rising_edge(clk_i) then
            case state is
                when S_IDLE =>
                    lcd_en <= '0';
                    if wb_stb_i = '1' and wb_we_i = '1' then
                        lcd_data  <= pend_data;
                        lcd_rs    <= pend_rs;
                        busy      <= '1';
                        state     <= S_PULSE;
                        delay_cnt <= EN_PULSE_C;
                    end if;

                when S_PULSE =>
                    lcd_en <= '1';
                    if delay_cnt = 1 then
                        lcd_en    <= '0';
                        state     <= S_DELAY;
                        if is_long_cmd = '1' then
                            delay_cnt <= DELAY_LONG_C;
                        else
                            delay_cnt <= DELAY_NORM_C;
                        end if;
                    else
                        delay_cnt <= delay_cnt - 1;
                    end if;

                when S_DELAY =>
                    lcd_en <= '0';
                    if delay_cnt = 1 then
                        busy  <= '0';
                        state <= S_IDLE;
                    else
                        delay_cnt <= delay_cnt - 1;
                    end if;
            end case;
        end if;
    end process;

end architecture rtl;
