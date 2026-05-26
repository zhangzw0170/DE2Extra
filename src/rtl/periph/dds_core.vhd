-- dds_core.vhd -- DDS oscillator with wavetable ROM
--
-- 32-bit phase accumulator, 48 kHz sample rate.
-- Tuning word: TW = f * 2^32 / 48000.
-- Wave table: 1024-entry MIF (4 waveforms x 256, 16-bit signed).
--   addr[9:8] = waveform select, addr[7:0] = phase index.
--
-- Controls: tuning_word_i, waveform_i, octave_i, volume_i.
-- Output: signed 16-bit sample, updated once per 48 kHz tick.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dds_core is
    generic (
        DEFAULT_WAVE : integer := 0;   -- 0=sin, 1=sq, 2=saw, 3=tri
        PHASE_OFFSET : integer := 0    -- wavetable index offset (0-255)
    );
    port (
        clk_i       : in  std_logic;
        rst_n_i     : in  std_logic;
        -- Controls (sampled on sample_tick_i)
        tuning_word_i : in std_logic_vector(31 downto 0);
        waveform_i  : in std_logic_vector(1 downto 0);  -- 00=sin, 01=sq, 10=saw, 11=tri
        octave_i    : in std_logic_vector(1 downto 0);  -- 00=0, 01=+1, 10=+2, 11=-1
        volume_i    : in std_logic_vector(7 downto 0);  -- 0=silent, 255=max
        -- 48 kHz sample tick (pulse)
        sample_tick_i : in std_logic;
        -- Output
        sample_o    : out std_logic_vector(15 downto 0)  -- signed 16-bit
    );
end entity dds_core;

architecture rtl of dds_core is

    signal phase_acc   : unsigned(31 downto 0);
    signal tw_reg      : unsigned(31 downto 0);
    signal wave_reg    : std_logic_vector(1 downto 0);
    signal oct_reg     : std_logic_vector(1 downto 0);
    signal vol_reg     : unsigned(7 downto 0);

    -- Wave table ROM: 1024 x 16-bit signed
    type wavetable_t is array(0 to 1023) of signed(15 downto 0);
    attribute ram_init_file : string;
    signal wavetable : wavetable_t;
    attribute ram_init_file of wavetable : signal is "wavetable_4wave.mif";

    signal rom_addr    : unsigned(9 downto 0);
    signal rom_data    : signed(15 downto 0);
    signal scaled      : signed(23 downto 0); -- 16-bit sample * 8-bit volume
    signal sample_raw  : signed(15 downto 0);

begin

    -- Sample controls on tick edge
    p_ctrl : process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            tw_reg   <= (others => '0');
            wave_reg <= std_logic_vector(to_unsigned(DEFAULT_WAVE, 2));
            oct_reg  <= "00";
            vol_reg  <= (others => '0');
        elsif rising_edge(clk_i) then
            if sample_tick_i = '1' then
                tw_reg   <= unsigned(tuning_word_i);
                wave_reg <= waveform_i;
                oct_reg  <= octave_i;
                vol_reg  <= unsigned(volume_i);
            end if;
        end if;
    end process;

    -- Phase accumulator: advance once per sample tick
    p_phase : process(clk_i, rst_n_i)
        variable octave_shift : integer range -1 to 2;
        variable tw_shifted   : unsigned(31 downto 0);
    begin
        if rst_n_i = '0' then
            phase_acc <= (others => '0');
        elsif rising_edge(clk_i) then
            if sample_tick_i = '1' then
                -- Octave shift: left shift for +1/+2, right shift for -1
                case oct_reg is
                    when "00"   => octave_shift := 0;
                    when "01"   => octave_shift := 1;
                    when "10"   => octave_shift := 2;
                    when "11"   => octave_shift := -1;
                    when others => octave_shift := 0;
                end case;

                if octave_shift >= 0 then
                    tw_shifted := shift_left(tw_reg, octave_shift);
                else
                    tw_shifted := shift_right(tw_reg, 1);
                end if;

                phase_acc <= phase_acc + tw_shifted;
            end if;
        end if;
    end process;

    -- Wave table address: [9:8]=waveform, [7:0]=phase top bits + offset
    rom_addr <= unsigned(wave_reg) & std_logic_vector(
        unsigned(phase_acc(31 downto 24)) + to_unsigned(PHASE_OFFSET, 8));

    -- ROM read (combinatorial)
    rom_data <= wavetable(to_integer(rom_addr));

    -- Volume scaling: sample * volume / 255
    -- Use 8x16 multiply, then divide by 256 (take upper 16 bits)
    p_vol : process(clk_i, rst_n_i)
        variable prod : signed(24 downto 0);
    begin
        if rst_n_i = '0' then
            sample_raw <= (others => '0');
            sample_o   <= (others => '0');
        elsif rising_edge(clk_i) then
            -- Multiply: 16-bit signed * 8-bit unsigned = 24-bit signed
            prod := rom_data * signed('0' & std_logic_vector(vol_reg));
            -- Take bits [23:8] to divide by 256
            sample_raw <= prod(23 downto 8);
            -- One cycle latency for pipeline
            sample_o <= sample_raw;
        end if;
    end process;

end architecture rtl;
