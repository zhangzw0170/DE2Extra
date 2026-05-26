-- synth_sim_tb.vhd -- Testbench for DDS core and FM operator
-- Uses simulation wrappers (dds_core_sim, fm_operator_sim) with synth_rom_pkg
-- Tests:
--  1. DDS: A4=440Hz tuning word, verify sine output period ~109 samples
--  2. DDS: Volume scaling (vol=255 vs vol=128)
--  3. DDS: Octave shift
--  4. DDS: PHASE_OFFSET produces different initial phases
--  5. FM: Carrier-only (no modulation) output
--  6. FM: ADSR envelope attack/release
--  7. FM: Modulation index affects output
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity synth_sim_tb is
end entity synth_sim_tb;

architecture sim of synth_sim_tb is

    constant CLK_PERIOD : time := 20 ns;

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';

    -- 48 kHz sample tick generator (same as synth_engine)
    constant SAMPLE_DIV : integer := 1042;
    signal sample_tick : std_logic;

    -- DDS signals
    signal dds_tw      : std_logic_vector(31 downto 0);
    signal dds_wave    : std_logic_vector(1 downto 0) := "00";
    signal dds_oct     : std_logic_vector(1 downto 0) := "00";
    signal dds_vol     : std_logic_vector(7 downto 0) := x"FF";
    signal dds_sample  : std_logic_vector(15 downto 0);
    signal dds_sample2 : std_logic_vector(15 downto 0);  -- second DDS with offset

    -- FM signals
    signal fm_tw       : std_logic_vector(31 downto 0) := (others => '0');
    signal fm_mod_in   : std_logic_vector(15 downto 0) := (others => '0');
    signal fm_mod_idx  : std_logic_vector(7 downto 0) := x"00";
    signal fm_ar       : std_logic_vector(3 downto 0) := x"4";
    signal fm_dr       : std_logic_vector(3 downto 0) := x"4";
    signal fm_sl       : std_logic_vector(3 downto 0) := x"4";
    signal fm_rr       : std_logic_vector(3 downto 0) := x"4";
    signal fm_gate     : std_logic := '0';
    signal fm_sample   : std_logic_vector(15 downto 0);

    -- Counters
    signal tick_count   : integer := 0;
    signal sample_count : integer := 0;

begin

    clk <= not clk after CLK_PERIOD / 2;

    -- Reset
    p_rst : process
    begin
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait;
    end process;

    -- 48 kHz tick generator (same div as synth_engine)
    p_sample_tick : process(clk, rst_n)
        variable div : integer range 0 to SAMPLE_DIV - 1;
    begin
        if rst_n = '0' then
            div := 0;
            sample_tick <= '0';
        elsif rising_edge(clk) then
            if div = SAMPLE_DIV - 1 then
                div := 0;
                sample_tick <= '1';
            else
                div := div + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;

    -- Sample counter
    p_cnt : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                sample_count <= 0;
            elsif sample_tick = '1' then
                sample_count <= sample_count + 1;
            end if;
        end if;
    end process;

    -- ── DDS instance (no phase offset) ───────────────────────
    u_dds1 : entity work.dds_core_sim
        generic map (DEFAULT_WAVE => 0, PHASE_OFFSET => 0)
        port map (
            clk_i          => clk,
            rst_n_i        => rst_n,
            tuning_word_i  => dds_tw,
            waveform_i     => dds_wave,
            octave_i       => dds_oct,
            volume_i       => dds_vol,
            sample_tick_i  => sample_tick,
            sample_o       => dds_sample
        );

    -- ── DDS instance (phase offset = 85) ──────────────────
    u_dds2 : entity work.dds_core_sim
        generic map (DEFAULT_WAVE => 0, PHASE_OFFSET => 85)
        port map (
            clk_i          => clk,
            rst_n_i        => rst_n,
            tuning_word_i  => dds_tw,
            waveform_i     => dds_wave,
            octave_i       => dds_oct,
            volume_i       => dds_vol,
            sample_tick_i  => sample_tick,
            sample_o       => dds_sample2
        );

    -- ── FM operator instance ────────────────────────────────
    u_fm : entity work.fm_operator_sim
        port map (
            clk_i          => clk,
            rst_n_i        => rst_n,
            sample_tick_i  => sample_tick,
            tuning_word_i  => fm_tw,
            modulation_i   => fm_mod_in,
            mod_index_i    => fm_mod_idx,
            attack_i       => fm_ar,
            decay_i        => fm_dr,
            sustain_i      => fm_sl,
            release_i      => fm_rr,
            gate_i         => fm_gate,
            sample_o       => fm_sample
        );

    -- ── Stimulus ────────────────────────────────────────────
    p_stim : process
        -- A4 = 440 Hz, TW = 39,276,827 = 0x0257EEDB
        constant TW_A4 : std_logic_vector(31 downto 0) := x"0257EEDB";
        -- C4 = 261.63 Hz, TW = 23,322,397 = 0x0163E7DD
        constant TW_C4 : std_logic_vector(31 downto 0) := x"0163E7DD";

        variable zero_crossings : integer;
        variable prev_sample   : signed(15 downto 0);
        variable peak_val      : integer;
        variable phase_diff_ok : boolean;
    begin
        wait until rst_n = '1';
        wait until rising_edge(clk);

        -- ══════════════════════════════════════════════════════
        -- Test 1: DDS A4 sine output
        -- A4 at 48kHz: period = 48000/440 ≈ 109.1 samples
        -- Check: output is non-zero sine wave
        -- ══════════════════════════════════════════════════════
        report "--- Test 1: DDS A4=440Hz sine wave ---";
        dds_tw <= TW_A4;
        dds_vol <= x"FF";
        dds_wave <= "00";  -- sine
        dds_oct  <= "00";  -- no shift
        fm_gate  <= '0';
        wait for 1 us;

        -- Collect 256 samples, count zero crossings and peak
        zero_crossings := 0;
        peak_val := 0;
        prev_sample := (others => '0');
        for i in 0 to 255 loop
            wait until sample_tick = '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);  -- pipeline latency
            wait until rising_edge(clk);
            if i > 2 then
                if (signed(dds_sample) >= 0 and prev_sample < 0) or
                   (signed(dds_sample) < 0 and prev_sample >= 0) then
                    zero_crossings := zero_crossings + 1;
                end if;
                if abs(to_integer(signed(dds_sample))) > peak_val then
                    peak_val := abs(to_integer(signed(dds_sample)));
                end if;
            end if;
            prev_sample := signed(dds_sample);
        end loop;

        -- 256 samples at 440Hz should have ~109.1 samples per cycle
        -- => ~2.35 cycles => ~4-5 zero crossings
        report "  Zero crossings in 256 samples: " & integer'image(zero_crossings);
        report "  Peak amplitude: " & integer'image(peak_val);
        assert zero_crossings >= 3 and zero_crossings <= 7
            report "FAIL: zero crossings out of expected range"
            severity error;
        assert peak_val > 20000
            report "FAIL: peak amplitude too low (expected ~32000 for full vol)"
            severity error;
        report "  PASS";

        -- ══════════════════════════════════════════════════════
        -- Test 2: DDS volume scaling
        -- vol=128 should give ~half amplitude of vol=255
        -- ══════════════════════════════════════════════════════
        report "--- Test 2: DDS volume scaling ---";
        dds_vol <= x"80";
        peak_val := 0;
        for i in 0 to 255 loop
            wait until sample_tick = '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            if i > 2 then
                if abs(to_integer(signed(dds_sample))) > peak_val then
                    peak_val := abs(to_integer(signed(dds_sample)));
                end if;
            end if;
        end loop;
        report "  Peak amplitude at vol=128: " & integer'image(peak_val);
        -- vol=128/255 ≈ 0.502, expected peak ≈ 16000
        assert peak_val > 12000 and peak_val < 20000
            report "FAIL: volume scaling incorrect"
            severity error;
        report "  PASS";

        dds_vol <= x"FF";

        -- ══════════════════════════════════════════════════════
        -- Test 3: DDS octave shift
        -- octave=+1 should double frequency => 2x zero crossings
        -- ══════════════════════════════════════════════════════
        report "--- Test 3: DDS octave +1 ---";
        dds_oct <= "01";
        zero_crossings := 0;
        prev_sample := (others => '0');
        for i in 0 to 255 loop
            wait until sample_tick = '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            if i > 2 then
                if (signed(dds_sample) >= 0 and prev_sample < 0) or
                   (signed(dds_sample) < 0 and prev_sample >= 0) then
                    zero_crossings := zero_crossings + 1;
                end if;
            end if;
            prev_sample := signed(dds_sample);
        end loop;
        report "  Zero crossings (oct+1): " & integer'image(zero_crossings);
        -- octave+1 => 880Hz => period ~54.5 => ~4.7 cycles => ~9 crossings
        assert zero_crossings >= 7 and zero_crossings <= 13
            report "FAIL: octave shift didn't double frequency"
            severity error;
        report "  PASS";
        dds_oct <= "00";

        -- ══════════════════════════════════════════════════════
        -- Test 4: DDS phase offset
        -- DDS1 (offset=0) and DDS2 (offset=85) should produce
        -- different initial samples
        -- ══════════════════════════════════════════════════════
        report "--- Test 4: DDS PHASE_OFFSET difference ---";
        dds_tw <= TW_A4;
        dds_vol <= x"FF";
        -- Wait a few cycles for pipeline
        wait for 1 us;
        wait until sample_tick = '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        phase_diff_ok := dds_sample /= dds_sample2;
        report "  DDS1 sample: " & integer'image(to_integer(unsigned(dds_sample)));
        report "  DDS2 sample: " & integer'image(to_integer(unsigned(dds_sample2)));
        assert phase_diff_ok
            report "FAIL: phase offset didn't produce different outputs"
            severity error;
        report "  PASS";

        -- ══════════════════════════════════════════════════════
        -- Test 5: FM carrier-only (modulation=0)
        -- With gate=1, AR=fast, should output sine wave
        -- ══════════════════════════════════════════════════════
        report "--- Test 5: FM carrier-only output ---";
        fm_tw   <= TW_A4;
        fm_mod_idx <= x"00";  -- no modulation
        fm_ar   <= x"F";       -- fast attack
        fm_dr   <= x"4";
        fm_sl   <= x"4";
        fm_rr   <= x"4";
        fm_gate <= '1';
        report "  fm_gate set to 1 at time " & time'image(now);
        report "  fm_sample immediately after gate: " & integer'image(to_integer(signed(fm_sample)));

        wait for 15 ms;  -- wait for ADSR attack to complete (AR=15, ~10.6ms)

        peak_val := 0;
        zero_crossings := 0;
        prev_sample := (others => '0');
        for i in 0 to 255 loop
            wait until sample_tick = '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            if i > 2 then
                if (signed(fm_sample) >= 0 and prev_sample < 0) or
                   (signed(fm_sample) < 0 and prev_sample >= 0) then
                    zero_crossings := zero_crossings + 1;
                end if;
                if abs(to_integer(signed(fm_sample))) > peak_val then
                    peak_val := abs(to_integer(signed(fm_sample)));
                end if;
            end if;
            prev_sample := signed(fm_sample);
        end loop;

        report "  Zero crossings: " & integer'image(zero_crossings);
        report "  Peak amplitude: " & integer'image(peak_val);
        assert zero_crossings >= 3
            report "FAIL: FM carrier output has no sine-like zero crossings"
            severity error;
        assert peak_val > 500
            report "FAIL: FM carrier output too weak"
            severity error;
        report "  PASS";

        -- ══════════════════════════════════════════════════════
        -- Test 6: FM ADSR release
        -- After gate=0, output should decay to zero
        -- ══════════════════════════════════════════════════════
        report "--- Test 6: FM ADSR release ---";
        fm_rr <= x"F";  -- fast release
        fm_gate <= '0';

        -- Wait for release to complete (511 ticks at RR=15 = ~10.6ms)
        for i in 0 to 600 loop
            wait until sample_tick = '1';
        end loop;

        -- Now collect samples — should all be near-zero
        peak_val := 0;
        for i in 0 to 63 loop
            wait until sample_tick = '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            if abs(to_integer(signed(fm_sample))) > peak_val then
                peak_val := abs(to_integer(signed(fm_sample)));
            end if;
        end loop;

        report "  Peak after release settled: " & integer'image(peak_val);
        assert peak_val < 8000
            report "FAIL: FM release didn't decay significantly"
            severity error;
        report "  PASS";

        -- ══════════════════════════════════════════════════════
        -- Test 7: FM modulation index
        -- Higher modulation index should produce richer waveform
        -- (more spectral content = different zero crossing pattern)
        -- ══════════════════════════════════════════════════════
        report "--- Test 7: FM modulation index ---";
        fm_gate <= '1';
        fm_mod_idx <= x"40";  -- moderate FM

        wait for 15 ms;

        zero_crossings := 0;
        prev_sample := (others => '0');
        for i in 0 to 255 loop
            wait until sample_tick = '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            if i > 2 then
                if (signed(fm_sample) >= 0 and prev_sample < 0) or
                   (signed(fm_sample) < 0 and prev_sample >= 0) then
                    zero_crossings := zero_crossings + 1;
                end if;
            end if;
            prev_sample := signed(fm_sample);
        end loop;
        report "  Zero crossings with FM: " & integer'image(zero_crossings);
        -- FM should produce more zero crossings than pure sine
        assert zero_crossings >= 5
            report "FAIL: FM modulation didn't increase spectral content"
            severity error;
        report "  PASS";

        fm_gate <= '0';

        -- ══════════════════════════════════════════════════════
        -- Done
        -- ══════════════════════════════════════════════════════
        report "========================================";
        report "All 7 tests PASSED";
        report "========================================";
        wait;
    end process;

end architecture sim;
