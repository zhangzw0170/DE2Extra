-- i2s_tx.vhd -- I2S transmitter for WM8731 (slave mode, FPGA-generated clocks)
--
-- Matches Terasic DE2-115 Synthesizer AUDIO_DAC.v pattern:
--   - Data output is combinatorial: oAUD_DATA = sample[~bit_cnt]
--   - Bit counter incremented on BCLK falling edge (registered)
--   - Shift register loaded on LRCK edge
-- BCLKINV=1 in WM8731: codec samples on physical BCLK falling edge.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_tx is
    port (
        clk_50m_i     : in  std_logic;
        rst_n_i       : in  std_logic;
        bclk_i        : in  std_logic;   -- FPGA-generated
        lrck_i        : in  std_logic;   -- FPGA-generated
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
    signal bclk_fall : std_logic;
    signal lrck_d    : std_logic;
    signal lrck_edge  : std_logic;
    signal is_left   : std_logic;

begin

    -- Edge detection (synchronized to 50 MHz)
    p_sync : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            bclk_d    <= '0';
            bclk_fall <= '0';
            lrck_d    <= '0';
            lrck_edge  <= '0';
            is_left   <= '1';
        elsif rising_edge(clk_50m_i) then
            bclk_d <= bclk_i;
            bclk_fall <= not bclk_i and bclk_d;

            lrck_d    <= lrck_i;
            if (lrck_i and not lrck_d) = '1' then
                is_left  <= '1';
                lrck_edge <= '1';
            elsif (not lrck_i and lrck_d) = '1' then
                is_left  <= '0';
                lrck_edge <= '1';
            else
                lrck_edge <= '0';
            end if;
        end if;
    end process;

    -- Sample capture: buffer on LRCK edge (double-buffer)
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
        end if;
    end process;

    -- Bit counter: increments on BCLK falling edge (Terasic pattern)
    p_bitcnt : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            shift_reg <= (others => '0');
            bit_cnt   <= 0;
        elsif rising_edge(clk_50m_i) then
            if lrck_edge = '1' then
                if is_left = '1' then
                    shift_reg <= buf_left;
                else
                    shift_reg <= buf_right;
                end if;
                bit_cnt <= 15;
            elsif bclk_fall = '1' then
                bit_cnt <= bit_cnt - 1;
            end if;
        end if;
    end process;

    -- Combinatorial data output: MSB first via bit-reverse indexing
    -- Terasic: assign oAUD_DATA = Sin_Out[~SEL_Cont]
    -- dacdat_o is valid one cycle after bclk_fall (pipeline delay)
    p_output : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            dacdat_o <= '0';
        elsif rising_edge(clk_50m_i) then
            if bit_cnt = 15 then
                -- No valid data before first BCLK edge of frame
                dacdat_o <= shift_reg(0);
            else
                -- MSB first: shift_reg(15) when bit_cnt=14, then
                -- shift_reg(14) when bit_cnt=13, etc.
                -- Pipeline: output follows bit_cnt by one cycle
                dacdat_o <= shift_reg(15 - bit_cnt);
            end if;
        end if;
    end process;

end architecture rtl;
