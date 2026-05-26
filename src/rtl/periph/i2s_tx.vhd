-- i2s_tx.vhd -- I2S transmitter for WM8731 (slave mode)
--
-- WM8731 generates BCLK and LRCK in slave mode.
-- FPGA provides MCLK and serial DAC data.
-- Data changes on BCLK falling edge (I2S standard).
-- Double-buffered: samples captured on LRCK edge, output next frame.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_tx is
    port (
        clk_50m_i     : in  std_logic;
        rst_n_i       : in  std_logic;
        bclk_i        : in  std_logic;   -- WM8731 generated
        lrck_i        : in  std_logic;   -- WM87360 generated
        sample_left_i : in  std_logic_vector(15 downto 0);
        sample_right_i: in  std_logic_vector(15 downto 0);
        dacdat_o      : out std_logic
    );
end entity i2s_tx;

architecture rtl of i2s_tx is

    signal buf_left  : std_logic_vector(15 downto 0);
    signal buf_right : std_logic_vector(15 downto 0);
    signal shift_reg : std_logic_vector(15 downto 0);
    signal bit_cnt   : integer range 0 to 15;

    -- Edge detection
    signal bclk_d    : std_logic;
    signal bclk_rise : std_logic;
    signal bclk_fall : std_logic;
    signal lrck_d    : std_logic;
    signal lrck_edge  : std_logic; -- pulse on any LRCK edge
    signal is_left   : std_logic;

begin

    -- Edge detection (synchronized to 50 MHz)
    p_sync : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            bclk_d    <= '0';
            bclk_rise <= '0';
            bclk_fall <= '0';
            lrck_d    <= '0';
            lrck_edge  <= '0';
            is_left   <= '1';
        elsif rising_edge(clk_50m_i) then
            bclk_d <= bclk_i;
            bclk_rise <= bclk_i and not bclk_d;
            bclk_fall <= not bclk_i and bclk_d;

            lrck_d    <= lrck_i;
            if (lrck_i and not lrck_d) = '1' then
                -- Rising LRCK = left channel
                is_left  <= '1';
                lrck_edge <= '1';
            elsif (not lrck_i and lrck_d) = '1' then
                -- Falling LRCK = right channel
                is_left  <= '0';
                lrck_edge <= '1';
            end if;
        end if;
    end process;

    -- Sample capture: buffer new samples on LRCK edge
    p_capture : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            buf_left  <= (others => '0');
            buf_right <= (others => '0');
        elsif rising_edge(clk_50m_i) then
            if lrck_edge = '1' then
                buf_left  <= sample_left_i;
                buf_right <= sample_right_i;
            end if;
        end process;

    -- Shift out on BCLK falling edge, defer LRCK load by one cycle
    p_shift : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            shift_reg <= (others => '0');
            bit_cnt   <= 0;
            dacdat_o  <= '0';
        elsif rising_edge(clk_50m_i) then
            -- Defer: load new channel data one cycle after LRCK edge
            -- (gives time for buf capture to settle)
            if lrck_edge = '1' then
                if is_left = '1' then
                    shift_reg <= buf_left;
                else
                    shift_reg <= buf_right;
                end if;
                bit_cnt <= 15;
            elsif bclk_fall = '1' then
                -- Output MSB on falling edge (I2S standard)
                dacdat_o  <= shift_reg(15);
                shift_reg <= shift_reg(14 downto 0) & '0';
                if bit_cnt > 0 then
                    bit_cnt <= bit_cnt - 1;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
