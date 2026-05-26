-- dds_core_sim.vhd -- Simulation wrapper for dds_core
-- Replaces ram_init_file MIF with synth_rom_pkg constant ROM
-- Only use this in ModelSim simulation, not in Quartus synthesis.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.synth_rom_pkg.all;

entity dds_core_sim is
    generic (
        DEFAULT_WAVE : integer := 0;
        PHASE_OFFSET : integer := 0
    );
    port (
        clk_i          : in  std_logic;
        rst_n_i        : in  std_logic;
        tuning_word_i  : in  std_logic_vector(31 downto 0);
        waveform_i     : in  std_logic_vector(1 downto 0);
        octave_i       : in  std_logic_vector(1 downto 0);
        volume_i       : in  std_logic_vector(7 downto 0);
        sample_tick_i  : in  std_logic;
        sample_o       : out std_logic_vector(15 downto 0)
    );
end entity dds_core_sim;

architecture rtl of dds_core_sim is

    signal phase_acc   : unsigned(31 downto 0);
    signal tw_reg      : unsigned(31 downto 0);
    signal wave_reg    : std_logic_vector(1 downto 0);
    signal oct_reg     : std_logic_vector(1 downto 0);
    signal vol_reg     : unsigned(7 downto 0);
    signal rom_addr    : unsigned(9 downto 0);
    signal rom_data    : signed(15 downto 0);
    signal scaled      : signed(23 downto 0);
    signal sample_raw  : signed(15 downto 0);

begin

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

    p_phase : process(clk_i, rst_n_i)
        variable octave_shift : integer range -1 to 2;
        variable tw_shifted   : unsigned(31 downto 0);
    begin
        if rst_n_i = '0' then
            phase_acc <= (others => '0');
        elsif rising_edge(clk_i) then
            if sample_tick_i = '1' then
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

    rom_addr <= unsigned(wave_reg) &
        (phase_acc(31 downto 24) + to_unsigned(PHASE_OFFSET, 8));
    rom_data <= WAVETABLE_ROM(to_integer(rom_addr));

    p_vol : process(clk_i, rst_n_i)
        variable prod : signed(24 downto 0);
    begin
        if rst_n_i = '0' then
            sample_raw <= (others => '0');
            sample_o   <= (others => '0');
        elsif rising_edge(clk_i) then
            prod := rom_data * signed('0' & std_logic_vector(vol_reg));
            sample_raw <= prod(23 downto 8);
            sample_o   <= std_logic_vector(sample_raw);
        end if;
    end process;

end architecture rtl;
