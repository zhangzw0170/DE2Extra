-- fm_operator.vhd -- FM synthesis operator (DX7-style, log-domain)
--
-- Based on OPL3 FPGA log-domain approach: zero hardware multipliers.
-- Phase accumulator + log_sine LUT + exp LUT + ADSR envelope.
-- Supports FM modulation: external modulator output added to phase.
--
-- Log-domain FM algorithm (sine waveform only):
--   1. phase_acc += tuning_word
--   2. final_phase = phase_acc[22:0] + modulation_input
--   3. theta = reflect_quadrant(final_phase[9:2])   -- 8-bit quarter-period
--   4. log_sin = log_sine_LUT[theta]               -- 256x12 ROM
--   5. level = log_sin + (envelope << 3) + BIAS    -- 13-bit: log-domain add
--   6. exp_val = exp_LUT[~level[7:0]]               -- 256x10 ROM
--   7. output = (exp_val << (15 - level[12:9])) ^ sign
--
-- ADSR envelope: 9-bit counter (0=loudest, 511=silent).
--   ATTACK: count 511 -> 0 at rate AR
--   DECAY:  count 0 -> sustain_level at rate DR
--   SUSTAIN: hold at sustain_level
--   RELEASE: count sustain_level -> 511 at rate RR
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fm_operator is
    port (
        clk_i          : in  std_logic;
        rst_n_i        : in  std_logic;
        -- 48 kHz sample tick
        sample_tick_i  : in  std_logic;
        -- Tuning word (TW = f * 2^32 / 48000)
        tuning_word_i  : in  std_logic_vector(31 downto 0);
        -- FM modulation input (signed, from another operator's output)
        modulation_i   : in  std_logic_vector(15 downto 0);
        -- Modulation index (0=carrier only, 127=max FM depth)
        mod_index_i    : in  std_logic_vector(7 downto 0);
        -- ADSR parameters (sampled on note-on)
        attack_i       : in  std_logic_vector(3 downto 0);
        decay_i        : in  std_logic_vector(3 downto 0);
        sustain_i      : in  std_logic_vector(3 downto 0);
        release_i      : in  std_logic_vector(3 downto 0);
        -- Gate: '1' = note on, '0' = note off (release)
        gate_i         : in  std_logic;
        -- Output (signed 16-bit, updated each sample tick)
        sample_o       : out std_logic_vector(15 downto 0)
    );
end entity fm_operator;

architecture rtl of fm_operator is

    -- ── Phase accumulator ────────────────────────────────────
    signal phase_acc    : unsigned(31 downto 0);
    signal tw_reg       : unsigned(31 downto 0);
    signal mod_index_reg : unsigned(7 downto 0);

    -- ── Modulation scaling ──────────────────────────────────
    -- modulation_i is 16-bit signed; scale by mod_index (0-127)
    -- mod_scaled = modulation * mod_index / 127
    -- Simplified: use top bits of modulation shifted by index
    signal mod_scaled   : signed(22 downto 0);

    -- ── Phase with modulation ────────────────────────────────
    -- Use bits [22:0] of phase (gives 8 quadrants = 2 full sine cycles
    -- worth of resolution; top 2 bits select quadrant)
    signal final_phase  : unsigned(22 downto 0);
    signal sign_bit     : std_logic;
    signal theta        : unsigned(7 downto 0);

    -- ── Log-sine LUT (256x12) ───────────────────────────────
    type log_sine_t is array(0 to 255) of unsigned(11 downto 0);
    attribute ram_init_file : string;
    signal log_sine_lut : log_sine_t;
    attribute ram_init_file of log_sine_lut : signal is "fm_log_sine.mif";

    -- ── Exp LUT (256x10) ────────────────────────────────────
    type exp_lut_t is array(0 to 255) of unsigned(9 downto 0);
    attribute ram_init_file2 : string;
    signal exp_lut : exp_lut_t;
    attribute ram_init_file2 of exp_lut : signal is "fm_exp.mif";

    -- ── Log-domain pipeline ─────────────────────────────────
    signal log_sin_val  : unsigned(11 downto 0);
    signal level        : unsigned(12 downto 0);  -- 13-bit: [12:9]=exp, [7:0]=mantissa
    signal exp_val      : unsigned(9 downto 0);
    signal exp_shifted  : unsigned(15 downto 0);

    -- Bias so log_sin_min (352) maps to level[12:9]=9 (shift=6, max usable)
    constant LEVEL_BIAS : unsigned(11 downto 0) := to_unsigned(1952, 12);

    -- ── ADSR envelope ───────────────────────────────────────
    type env_state_t is (S_ATTACK, S_DECAY, S_SUSTAIN, S_RELEASE, S_OFF);
    signal env_state    : env_state_t;
    signal env_cnt      : unsigned(8 downto 0);  -- 0=loud, 511=silent
    signal env_level    : unsigned(11 downto 0);  -- shifted for log domain
    signal env_rate_cnt : unsigned(7 downto 0);   -- sub-counter for slow rates

    -- Sample controls
    signal gate_reg     : std_logic;
    signal gate_prev    : std_logic;

    -- ADSR params
    signal ar_reg       : unsigned(3 downto 0);
    signal dr_reg       : unsigned(3 downto 0);
    signal sl_reg       : unsigned(3 downto 0);
    signal rr_reg       : unsigned(3 downto 0);

begin

    -- ── Sample controls on tick ──────────────────────────────
    p_ctrl : process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            tw_reg        <= (others => '0');
            mod_index_reg <= (others => '0');
            gate_reg      <= '0';
            gate_prev     <= '0';
            ar_reg        <= (others => '0');
            dr_reg        <= x"0";
            sl_reg        <= x"0";
            rr_reg        <= x"0";
        elsif rising_edge(clk_i) then
            if sample_tick_i = '1' then
                gate_prev <= gate_reg;
                tw_reg        <= unsigned(tuning_word_i);
                mod_index_reg <= unsigned(mod_index_i);
                gate_reg      <= gate_i;
                ar_reg        <= unsigned(attack_i);
                dr_reg        <= unsigned(decay_i);
                sl_reg        <= unsigned(sustain_i);
                rr_reg        <= unsigned(release_i);
            end if;
        end if;
    end process;

    -- ── Modulation scaling ───────────────────────────────────
    -- mod_scaled = signed(modulation) * mod_index / 127
    -- Use: (modulation[15:8]) * mod_index, approximately
    -- This is a simple 8x8 multiply feeding into 23-bit phase addition
    p_mod_scale : process(clk_i)
        variable prod : signed(24 downto 0);
    begin
        if rising_edge(clk_i) then
            if mod_index_reg = 0 or gate_reg = '0' then
                mod_scaled <= (others => '0');
            else
                -- Take top 8 bits of modulation (signed) * index
                prod := resize(shift_right(signed(modulation_i), 7), 16) *
                        signed('0' & std_logic_vector(mod_index_reg));
                mod_scaled <= resize(prod, 23);
            end if;
        end if;
    end process;

    -- ── Phase accumulator ───────────────────────────────────
    p_phase : process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            phase_acc <= (others => '0');
        elsif rising_edge(clk_i) then
            if sample_tick_i = '1' then
                phase_acc <= phase_acc + tw_reg;
            end if;
        end if;
    end process;

    -- ── Final phase = phase[22:0] + modulation ───────────────
    final_phase <= resize(phase_acc, 23) +
                   unsigned(std_logic_vector(mod_scaled));

    -- ── Quadrant reflection (sine waveform) ─────────────────
    -- phase[22:10] = quadrant (0-3): 00=Q1(rising), 01=Q2(falling),
    --   10=Q3(falling, negative), 11=Q4(rising, negative)
    -- theta = reflected 8-bit index into quarter-period LUT
    sign_bit <= final_phase(10);  -- MSB of quadrant = negative half
    p_theta : process(final_phase)
        variable quad_msb : std_logic;
    begin
        quad_msb := final_phase(9);  -- LSB of quadrant = which half of period
        if quad_msb = '0' then
            theta <= final_phase(7 downto 0);
        else
            theta <= not final_phase(7 downto 0);
        end if;
    end process;

    -- ── Log-sine LUT lookup ─────────────────────────────────
    log_sin_val <= log_sine_lut(to_integer(theta));

    -- ── ADSR envelope generator ─────────────────────────────
    p_env : process(clk_i, rst_n_i)
        variable rate_max : unsigned(7 downto 0);
        variable sustain_level : unsigned(8 downto 0);
        variable sl_int : integer;
        function calc_rate(rate : unsigned(3 downto 0)) return unsigned is
            variable r : integer;
        begin
            if rate = 0 then return to_unsigned(255, 8);
            else
                r := to_integer(rate) * 17;
                return resize(to_unsigned(255, 8) - to_unsigned(r, 8), 8);
            end if;
        end function;
    begin
        if rst_n_i = '0' then
            env_state    <= S_OFF;
            env_cnt      <= to_unsigned(511, 9);
            env_rate_cnt <= (others => '0');
            env_level    <= (others => '0');
        elsif rising_edge(clk_i) then
            if sample_tick_i = '1' then
                -- Gate edge detection
                if gate_reg = '1' and gate_prev = '0' then
                    -- Note on: start attack
                    env_state    <= S_ATTACK;
                    env_cnt      <= to_unsigned(511, 9);
                    env_rate_cnt <= (others => '0');
                elsif gate_reg = '0' and gate_prev = '1' then
                    -- Note off: start release from current level
                    env_state    <= S_RELEASE;
                    env_rate_cnt <= (others => '0');
                end if;

                -- Envelope rate counter
                case env_state is
                    when S_ATTACK =>
                        rate_max := calc_rate(ar_reg);
                        if env_rate_cnt < rate_max then
                            env_rate_cnt <= env_rate_cnt + 1;
                        else
                            env_rate_cnt <= (others => '0');
                            if env_cnt > 0 then
                                env_cnt <= env_cnt - 1;
                            else
                                env_state <= S_DECAY;
                            end if;
                        end if;

                    when S_DECAY =>
                        rate_max := calc_rate(dr_reg);
                        sl_int := to_integer(sl_reg) * 34;
                        sustain_level := to_unsigned(511, 9) -
                                        resize(shift_left(to_unsigned(1, 9), 5) - to_unsigned(sl_int, 9), 9);
                        if env_rate_cnt < rate_max then
                            env_rate_cnt <= env_rate_cnt + 1;
                        else
                            env_rate_cnt <= (others => '0');
                            if env_cnt < sustain_level then
                                env_cnt <= env_cnt + 1;
                            else
                                env_state <= S_SUSTAIN;
                            end if;
                        end if;

                    when S_SUSTAIN =>
                        null; -- hold current level

                    when S_RELEASE =>
                        rate_max := calc_rate(rr_reg);
                        if env_rate_cnt < rate_max then
                            env_rate_cnt <= env_rate_cnt + 1;
                        else
                            env_rate_cnt <= (others => '0');
                            if env_cnt < 511 then
                                env_cnt <= env_cnt + 1;
                            else
                                env_state <= S_OFF;
                            end if;
                        end if;

                    when S_OFF =>
                        env_cnt <= to_unsigned(511, 9);
                end case;

                -- Convert envelope count to log-domain shift
                -- env_cnt=0 (loud) -> env_level=0 (no attenuation)
                -- env_cnt=511 (silent) -> env_level=4088 (max attenuation)
                env_level <= shift_left(resize(env_cnt, 12), 3);
            end if;
        end if;
    end process;

    -- ── Log-domain level = log_sin + envelope + bias ─────────
    -- Bias ensures log_sin_min (352) maps to level[12:9]=9 (shift=6)
    p_level : process(clk_i)
        variable sum_v : unsigned(13 downto 0);
    begin
        if rising_edge(clk_i) then
            if sample_tick_i = '1' then
                sum_v := ('0' & '0' & log_sin_val) + ('0' & env_level) + ('0' & '0' & LEVEL_BIAS);
                if sum_v > 8191 then
                    level <= to_unsigned(8191, 13);
                else
                    level <= sum_v(12 downto 0);
                end if;
            end if;
        end if;
    end process;

    -- ── Exp LUT + shift ─────────────────────────────────────
    -- output = exp_LUT[~level[7:0]] << (15 - level[12:9])
    p_exp : process(clk_i)
        variable exp_addr  : integer range 0 to 255;
        variable shift_amt : integer range 0 to 15;
        variable exp_out   : unsigned(9 downto 0);
    begin
        if rising_edge(clk_i) then
            if sample_tick_i = '1' then
                exp_addr  := to_integer(not level(7 downto 0));
                shift_amt := to_integer(level(12 downto 9));
                exp_out   := exp_lut(exp_addr);

                if shift_amt >= 15 then
                    exp_shifted <= (others => '0');
                else
                    exp_shifted <= shift_left(resize(exp_out, 16), 15 - shift_amt);
                end if;
            end if;
        end if;
    end process;

    -- ── Output with sign ────────────────────────────────────
    p_out : process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            sample_o <= (others => '0');
        elsif rising_edge(clk_i) then
            if sign_bit = '1' then
                sample_o <= std_logic_vector(not exp_shifted);
            else
                sample_o <= std_logic_vector(exp_shifted);
            end if;
        end if;
    end process;

end architecture rtl;
