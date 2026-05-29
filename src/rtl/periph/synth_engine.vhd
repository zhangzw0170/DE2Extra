-- synth_engine.vhd -- Dual-track synthesizer Wishbone slave
--
-- Integrates: wm8731_ctrl (I2C), i2s_tx (I2S), 6x dds_core (3xOSC),
-- 4x fm_operator (DX7 FM), mode mux, mixer, and Wishbone register file.
--
-- Wishbone address map (5-bit word address):
--   0x00: CTRL   [0]=mute, [2:1]=mode (00=3xOSC, 01=DX7), [4:3]=volume
--   0x01: STATUS [0]=codec_ready
--   0x02: Track1 NOTE  [7:0]=MIDI note (0=release)
--   0x03: Track1 OSC1 [1:0]=wave, [3:2]=octave, [15:8]=vol
--   0x04: Track1 OSC2
--   0x05: Track1 OSC3
--   0x06: Track1 DX7  [7:0]=ratio, [15:8]=index
--   0x07: Track1 ADSR  [3:0]=AR, [7:4]=DR, [11:8]=SL, [15:12]=RR
--   0x08: Track2 NOTE
--   0x09: Track2 OSC1
--   0x0A: Track2 OSC2
--   0x0B: Track2 OSC3
--   0x0C: Track2 DX7
--   0x0D: Track2 ADSR
--
-- Audio out: AUD_XCK, AUD_BCLK, AUD_DACLRCK, AUD_DACDAT, I2C_SCLK, I2C_SDAT
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity synth_engine is
    port (
        -- Clock and reset
        clk_i        : in  std_logic;
        rst_n_i      : in  std_logic;
        -- Wishbone slave
        wb_adr_i     : in  std_logic_vector(4 downto 0);
        wb_dat_i     : in  std_logic_vector(31 downto 0);
        wb_dat_o     : out std_logic_vector(31 downto 0);
        wb_we_i      : in  std_logic;
        wb_stb_i     : in  std_logic;
        wb_ack_o     : out std_logic;
        -- Audio codec (WM8731)
        aud_xck_o    : out std_logic;
        aud_bclk_i   : in  std_logic;    -- WM8731 slave mode: input
        aud_daclrck_i: in  std_logic;    -- WM8731 slave mode: input
        aud_dacdat_o : out std_logic;
        i2c_sclk_o   : out std_logic;
        i2c_sdat_o   : inout std_logic
    );
end entity synth_engine;

architecture rtl of synth_engine is

    -- ── 48 kHz sample tick generator from 50 MHz ─────────────
    -- 50_000_000 / 48_000 = 1041.67 -> use 1042
    constant SAMPLE_DIV : integer := 1042;
    signal sample_tick : std_logic;

    -- ── WM8731 I2C controller ──────────────────────────────────
    signal i2c_sclk : std_logic;
    signal codec_ready : std_logic;

    -- ── Wishbone registers ────────────────────────────────────
    signal ctrl_reg   : std_logic_vector(31 downto 0); -- 0x00
    signal status_reg : std_logic_vector(31 downto 0); -- 0x01 (read-only)

    -- Track 1 registers
    signal t1_note    : std_logic_vector(31 downto 0); -- 0x02
    signal t1_osc1    : std_logic_vector(31 downto 0); -- 0x03
    signal t1_osc2    : std_logic_vector(31 downto 0); -- 0x04
    signal t1_osc3    : std_logic_vector(31 downto 0); -- 0x05
    signal t1_dx7_ri  : std_logic_vector(31 downto 0); -- 0x06
    signal t1_dx7_adsr: std_logic_vector(31 downto 0); -- 0x07

    -- Track 2 registers
    signal t2_note    : std_logic_vector(31 downto 0); -- 0x08
    signal t2_osc1    : std_logic_vector(31 downto 0); -- 0x09
    signal t2_osc2    : std_logic_vector(31 downto 0); -- 0x0A
    signal t2_osc3    : std_logic_vector(31 downto 0); -- 0x0B
    signal t2_dx7_ri  : std_logic_vector(31 downto 0); -- 0x0C
    signal t2_dx7_adsr: std_logic_vector(31 downto 0); -- 0x0D

    -- ── MIDI note to tuning word ──────────────────────────────
    -- TW = f * 2^32 / 48000
    -- f = 440 * 2^((note - 69) / 12)
    -- Default: A4 = 440 Hz -> TW = 0x0257_EEDB
    signal mute       : std_logic;
    signal t1_tw      : std_logic_vector(31 downto 0);
    signal t2_tw      : std_logic_vector(31 downto 0);

    -- ── DDS instances ─────────────────────────────────────────
    -- Track 1: 3 oscillators
    signal t1_osc1_sample : std_logic_vector(15 downto 0);
    signal t1_osc2_sample : std_logic_vector(15 downto 0);
    signal t1_osc3_sample : std_logic_vector(15 downto 0);
    -- Track 2: 3 oscillators
    signal t2_osc1_sample : std_logic_vector(15 downto 0);
    signal t2_osc2_sample : std_logic_vector(15 downto 0);
    signal t2_osc3_sample : std_logic_vector(15 downto 0);

    -- ── Mixer output ──────────────────────────────────────────
    signal mix_l_clip : std_logic_vector(15 downto 0);
    signal mix_r_clip : std_logic_vector(15 downto 0);

    -- ── FM operator signals ──────────────────────────────────
    -- Track 1: modulator + carrier
    signal t1_mod_sample : std_logic_vector(15 downto 0);
    signal t1_car_sample  : std_logic_vector(15 downto 0);
    signal t1_gate        : std_logic;
    -- Track 2: modulator + carrier
    signal t2_mod_sample : std_logic_vector(15 downto 0);
    signal t2_car_sample  : std_logic_vector(15 downto 0);
    signal t2_gate        : std_logic;

    -- Modulator tuning words (base TW scaled by ratio)
    signal t1_mod_tw     : std_logic_vector(31 downto 0);
    signal t2_mod_tw     : std_logic_vector(31 downto 0);

    -- ── Mode mux outputs ──────────────────────────────────────
    signal synth_left  : std_logic_vector(15 downto 0);
    signal synth_right : std_logic_vector(15 downto 0);

    -- ── Synthesis mode ────────────────────────────────────────
    signal synth_mode : std_logic_vector(1 downto 0);

    -- ── Master volume ─────────────────────────────────────────
    signal master_vol_shift : integer range 0 to 3;

    -- ── I2S ──────────────────────────────────────────────────
    signal i2s_left  : std_logic_vector(15 downto 0);
    signal i2s_right : std_logic_vector(15 downto 0);

    -- ── AUD_XCK: 50/4 = 12.5 MHz ─────────────────────────
    -- WM8731 register 8 = 0x0006: USB mode, PLL enabled, accepts
    -- MCLK in range 11.2896-12.288 MHz (48 kHz x 256x).
    signal xck_div   : unsigned(1 downto 0);
    signal aud_xck_r : std_logic;

begin

    -- ── 48 kHz sample tick ────────────────────────────────────
    p_sample_tick : process(clk_i, rst_n_i)
        variable div : integer range 0 to SAMPLE_DIV - 1;
    begin
        if rst_n_i = '0' then
            div := 0;
            sample_tick <= '0';
        elsif rising_edge(clk_i) then
            if div = SAMPLE_DIV - 1 then
                div := 0;
                sample_tick <= '1';
            else
                div := div + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;

    -- ── AUD_XCK: ~12.5 MHz from 50 MHz (divide by 4) ───────
    -- WM8731 with internal PLL (reg 0x08 bit 2) can accept this
    p_xck : process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            xck_div <= (others => '0');
            aud_xck_r <= '0';
        elsif rising_edge(clk_i) then
            xck_div <= xck_div + 1;
            aud_xck_r <= xck_div(1);
        end if;
    end process;
    aud_xck_o <= aud_xck_r;

    -- ── WM8731 I2C controller ──────────────────────────────────
    u_i2c : entity work.wm8731_ctrl
        port map (
            clk_i     => clk_i,
            rst_n_i   => rst_n_i,
            i2c_sclk_o => i2c_sclk,
            i2c_sdat   => i2c_sdat_o,
            ready_o   => codec_ready
        );
    i2c_sclk_o <= i2c_sclk;

    -- ── Status register ───────────────────────────────────────
    status_reg <= (0 => codec_ready, others => '0');

    -- ── Wishbone register file ────────────────────────────────
    p_wb : process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            ctrl_reg    <= (others => '0');
            t1_note     <= (others => '0');
            t1_osc1     <= (others => '0');
            t1_osc2     <= (others => '0');
            t1_osc3     <= (others => '0');
            t1_dx7_ri   <= (others => '0');
            t1_dx7_adsr <= (others => '0');
            t2_note     <= (others => '0');
            t2_osc1     <= (others => '0');
            t2_osc2     <= (others => '0');
            t2_osc3     <= (others => '0');
            t2_dx7_ri   <= (others => '0');
            t2_dx7_adsr <= (others => '0');
            wb_ack_o    <= '0';
            wb_dat_o    <= (others => '0');
        elsif rising_edge(clk_i) then
            wb_ack_o <= '0';
            wb_dat_o  <= (others => '0');

            if wb_stb_i = '1' and wb_we_i = '1' then
                wb_ack_o <= '1';
                case wb_adr_i is
                    when "00000" => ctrl_reg    <= wb_dat_i;
                    when "00010" => t1_note     <= wb_dat_i;
                    when "00011" => t1_osc1     <= wb_dat_i;
                    when "00100" => t1_osc2     <= wb_dat_i;
                    when "00101" => t1_osc3     <= wb_dat_i;
                    when "00110" => t1_dx7_ri   <= wb_dat_i;
                    when "00111" => t1_dx7_adsr <= wb_dat_i;
                    when "01000" => t2_note     <= wb_dat_i;
                    when "01001" => t2_osc1     <= wb_dat_i;
                    when "01010" => t2_osc2     <= wb_dat_i;
                    when "01011" => t2_osc3     <= wb_dat_i;
                    when "01100" => t2_dx7_ri   <= wb_dat_i;
                    when "01101" => t2_dx7_adsr <= wb_dat_i;
                    when others => null;
                end case;
            elsif wb_stb_i = '1' then
                wb_ack_o <= '1';
                case wb_adr_i is
                    when "00001" => wb_dat_o <= status_reg;
                    when others => null;
                end case;
            end if;
        end if;
    end process;

    -- ── Tuning word from firmware ────────────────────────────
    -- Firmware writes the precomputed TW (32-bit) into the NOTE register.
    -- NOTE[7:0] = MIDI note for firmware convenience, but TW[31:0] is
    -- stored in the upper bits for backward compat.
    -- Simplified: firmware directly writes TW to OSC1 bits [31:16] of
    -- the NOTE register, or we use a separate mechanism.
    -- Actually: let's redefine: NOTE[31:8] = tuning word (from firmware),
    -- NOTE[7:0] = MIDI note (for display only).
    -- The DDS gets the TW from bits [31:8] shifted left by 8, or better:
    -- we use the full 32-bit register value as the TW.
    -- Firmware should write: note_reg = tuning_table[midi_note]
    t1_tw <= t1_note; -- full 32-bit = tuning word
    t2_tw <= t2_note;

    mute <= ctrl_reg(0);
    master_vol_shift <= to_integer(unsigned(ctrl_reg(4 downto 3)));
    synth_mode <= ctrl_reg(2 downto 1);

    -- ── Gate detection: note != 0 means note-on ───────────────
    t1_gate <= '1' when unsigned(t1_note) /= 0 else '0';
    t2_gate <= '1' when unsigned(t2_note) /= 0 else '0';

    -- ── Modulator TW: base TW scaled by ratio ─────────────────
    -- ratio field [7:0]: 0=0.5x, 1=1x, 2=2x, 3=3x, 4=4x
    p_mod_tw : process(clk_i)
    begin
        if rising_edge(clk_i) then
            case t1_dx7_ri(7 downto 0) is
                when x"00"   => t1_mod_tw <= std_logic_vector(shift_right(unsigned(t1_tw), 1));
                when x"01"   => t1_mod_tw <= t1_tw;
                when others   => t1_mod_tw <= std_logic_vector(
                    shift_left(unsigned(t1_tw), to_integer(unsigned(t1_dx7_ri(1 downto 0))) - 1));
            end case;
            case t2_dx7_ri(7 downto 0) is
                when x"00"   => t2_mod_tw <= std_logic_vector(shift_right(unsigned(t2_tw), 1));
                when x"01"   => t2_mod_tw <= t2_tw;
                when others   => t2_mod_tw <= std_logic_vector(
                    shift_left(unsigned(t2_tw), to_integer(unsigned(t2_dx7_ri(1 downto 0))) - 1));
            end case;
        end if;
    end process;

    -- ── Track 1 DDS: 3 oscillators ───────────────────────────
    u_t1_osc1 : entity work.dds_core
        generic map (DEFAULT_WAVE => 0, PHASE_OFFSET => 0)
        port map (
            clk_i        => clk_i,
            rst_n_i      => rst_n_i,
            tuning_word_i => t1_tw,
            waveform_i   => t1_osc1(1 downto 0),
            octave_i     => t1_osc1(3 downto 2),
            volume_i     => t1_osc1(15 downto 8),
            sample_tick_i => sample_tick,
            sample_o     => t1_osc1_sample
        );

    u_t1_osc2 : entity work.dds_core
        generic map (DEFAULT_WAVE => 0, PHASE_OFFSET => 85)
        port map (
            clk_i        => clk_i,
            rst_n_i      => rst_n_i,
            tuning_word_i => t1_tw,
            waveform_i   => t1_osc2(1 downto 0),
            octave_i     => t1_osc2(3 downto 2),
            volume_i     => t1_osc2(15 downto 8),
            sample_tick_i => sample_tick,
            sample_o     => t1_osc2_sample
        );

    u_t1_osc3 : entity work.dds_core
        generic map (DEFAULT_WAVE => 0, PHASE_OFFSET => 170)
        port map (
            clk_i        => clk_i,
            rst_n_i      => rst_n_i,
            tuning_word_i => t1_tw,
            waveform_i   => t1_osc3(1 downto 0),
            octave_i     => t1_osc3(3 downto 2),
            volume_i     => t1_osc3(15 downto 8),
            sample_tick_i => sample_tick,
            sample_o     => t1_osc3_sample
        );

    -- ── Track 2 DDS: 3 oscillators ───────────────────────────
    u_t2_osc1 : entity work.dds_core
        generic map (DEFAULT_WAVE => 0, PHASE_OFFSET => 0)
        port map (
            clk_i        => clk_i,
            rst_n_i      => rst_n_i,
            tuning_word_i => t2_tw,
            waveform_i   => t2_osc1(1 downto 0),
            octave_i     => t2_osc1(3 downto 2),
            volume_i     => t2_osc1(15 downto 8),
            sample_tick_i => sample_tick,
            sample_o     => t2_osc1_sample
        );

    u_t2_osc2 : entity work.dds_core
        generic map (DEFAULT_WAVE => 0, PHASE_OFFSET => 85)
        port map (
            clk_i        => clk_i,
            rst_n_i      => rst_n_i,
            tuning_word_i => t2_tw,
            waveform_i   => t2_osc2(1 downto 0),
            octave_i     => t2_osc2(3 downto 2),
            volume_i     => t2_osc2(15 downto 8),
            sample_tick_i => sample_tick,
            sample_o     => t2_osc2_sample
        );

    u_t2_osc3 : entity work.dds_core
        generic map (DEFAULT_WAVE => 0, PHASE_OFFSET => 170)
        port map (
            clk_i        => clk_i,
            rst_n_i      => rst_n_i,
            tuning_word_i => t2_tw,
            waveform_i   => t2_osc3(1 downto 0),
            octave_i     => t2_osc3(3 downto 2),
            volume_i     => t2_osc3(15 downto 8),
            sample_tick_i => sample_tick,
            sample_o     => t2_osc3_sample
        );

    -- ── Track 1 FM: modulator + carrier ──────────────────────
    u_t1_mod : entity work.fm_operator
        port map (
            clk_i          => clk_i,
            rst_n_i        => rst_n_i,
            sample_tick_i  => sample_tick,
            tuning_word_i  => t1_mod_tw,
            modulation_i   => (others => '0'),  -- modulator has no modulation
            mod_index_i    => t1_dx7_ri(15 downto 8),
            attack_i       => t1_dx7_adsr(3 downto 0),
            decay_i        => t1_dx7_adsr(7 downto 4),
            sustain_i      => t1_dx7_adsr(11 downto 8),
            release_i      => t1_dx7_adsr(15 downto 12),
            gate_i         => t1_gate,
            sample_o       => t1_mod_sample
        );

    u_t1_car : entity work.fm_operator
        port map (
            clk_i          => clk_i,
            rst_n_i        => rst_n_i,
            sample_tick_i  => sample_tick,
            tuning_word_i  => t1_tw,
            modulation_i   => t1_mod_sample,  -- FM: modulator modulates carrier
            mod_index_i    => t1_dx7_ri(15 downto 8),
            attack_i       => t1_dx7_adsr(3 downto 0),
            decay_i        => t1_dx7_adsr(7 downto 4),
            sustain_i      => t1_dx7_adsr(11 downto 8),
            release_i      => t1_dx7_adsr(15 downto 12),
            gate_i         => t1_gate,
            sample_o       => t1_car_sample
        );

    -- ── Track 2 FM: modulator + carrier ──────────────────────
    u_t2_mod : entity work.fm_operator
        port map (
            clk_i          => clk_i,
            rst_n_i        => rst_n_i,
            sample_tick_i  => sample_tick,
            tuning_word_i  => t2_mod_tw,
            modulation_i   => (others => '0'),
            mod_index_i    => t2_dx7_ri(15 downto 8),
            attack_i       => t2_dx7_adsr(3 downto 0),
            decay_i        => t2_dx7_adsr(7 downto 4),
            sustain_i      => t2_dx7_adsr(11 downto 8),
            release_i      => t2_dx7_adsr(15 downto 12),
            gate_i         => t2_gate,
            sample_o       => t2_mod_sample
        );

    u_t2_car : entity work.fm_operator
        port map (
            clk_i          => clk_i,
            rst_n_i        => rst_n_i,
            sample_tick_i  => sample_tick,
            tuning_word_i  => t2_tw,
            modulation_i   => t2_mod_sample,
            mod_index_i    => t2_dx7_ri(15 downto 8),
            attack_i       => t2_dx7_adsr(3 downto 0),
            decay_i        => t2_dx7_adsr(7 downto 4),
            sustain_i      => t2_dx7_adsr(11 downto 8),
            release_i      => t2_dx7_adsr(15 downto 12),
            gate_i         => t2_gate,
            sample_o       => t2_car_sample
        );

    -- ── Mode mux: 3xOSC or DX7 output ────────────────────────
    p_mux : process(clk_i, rst_n_i)
        variable osc1_l, osc2_l, osc3_l : signed(17 downto 0);
        variable osc1_r, osc2_r, osc3_r : signed(17 downto 0);
        variable clamped_l, clamped_r : signed(15 downto 0);
    begin
        if rst_n_i = '0' then
            synth_left  <= (others => '0');
            synth_right <= (others => '0');
        elsif rising_edge(clk_i) then
            case synth_mode is
                when "01" =>
                    -- DX7 FM mode: carrier output
                    synth_left  <= t1_car_sample;
                    synth_right <= t2_car_sample;
                when others =>
                    -- 3xOSC mode (default): mix 3 DDS oscillators
                    osc1_l := resize(signed(t1_osc1_sample), 18)
                           + resize(signed(t1_osc2_sample), 18)
                           + resize(signed(t1_osc3_sample), 18);
                    if osc1_l > 32767 then
                        clamped_l := to_signed(32767, 16);
                    elsif osc1_l < -32768 then
                        clamped_l := to_signed(-32768, 16);
                    else
                        clamped_l := osc1_l(15 downto 0);
                    end if;

                    osc1_r := resize(signed(t2_osc1_sample), 18)
                           + resize(signed(t2_osc2_sample), 18)
                           + resize(signed(t2_osc3_sample), 18);
                    if osc1_r > 32767 then
                        clamped_r := to_signed(32767, 16);
                    elsif osc1_r < -32768 then
                        clamped_r := to_signed(-32768, 16);
                    else
                        clamped_r := osc1_r(15 downto 0);
                    end if;

                    synth_left  <= std_logic_vector(clamped_l);
                    synth_right <= std_logic_vector(clamped_r);
            end case;
        end if;
    end process;

    -- ── Mixer: master volume on mux output ────────────────────
    p_mix : process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            mix_l_clip  <= (others => '0');
            mix_r_clip  <= (others => '0');
            i2s_left    <= (others => '0');
            i2s_right   <= (others => '0');
        elsif rising_edge(clk_i) then
            if mute = '1' then
                mix_l_clip <= (others => '0');
                mix_r_clip <= (others => '0');
            else
                mix_l_clip <= std_logic_vector(
                    shift_right(signed(synth_left), master_vol_shift));
                mix_r_clip <= std_logic_vector(
                    shift_right(signed(synth_right), master_vol_shift));
            end if;

            -- Pipeline: I2S reads one cycle later
            i2s_left  <= mix_l_clip;
            i2s_right <= mix_r_clip;
        end if;
    end process;

    -- ── I2S transmitter ───────────────────────────────────────
    u_i2s : entity work.i2s_tx
        port map (
            clk_50m_i     => clk_i,
            rst_n_i       => rst_n_i,
            bclk_i        => aud_bclk_i,
            lrck_i        => aud_daclrck_i,
            sample_left_i  => i2s_left,
            sample_right_i => i2s_right,
            dacdat_o      => aud_dacdat_o
        );

end architecture rtl;
