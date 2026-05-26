-- fm_operator_sim.vhd -- Simulation wrapper for fm_operator
-- Replaces ram_init_file MIF with synth_rom_pkg constant ROM
-- Only use this in ModelSim simulation, not in Quartus synthesis.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.synth_rom_pkg.all;

entity fm_operator_sim is
    port (
        clk_i          : in  std_logic;
        rst_n_i        : in  std_logic;
        sample_tick_i  : in  std_logic;
        tuning_word_i  : in  std_logic_vector(31 downto 0);
        modulation_i   : in  std_logic_vector(15 downto 0);
        mod_index_i    : in  std_logic_vector(7 downto 0);
        attack_i       : in  std_logic_vector(3 downto 0);
        decay_i        : in  std_logic_vector(3 downto 0);
        sustain_i      : in  std_logic_vector(3 downto 0);
        release_i      : in  std_logic_vector(3 downto 0);
        gate_i         : in  std_logic;
        sample_o       : out std_logic_vector(15 downto 0)
    );
end entity fm_operator_sim;

architecture rtl of fm_operator_sim is

    signal phase_acc     : unsigned(31 downto 0);
    signal tw_reg        : unsigned(31 downto 0);
    signal mod_index_reg : unsigned(7 downto 0);
    signal mod_scaled    : signed(22 downto 0);
    signal final_phase   : unsigned(22 downto 0);
    signal sign_bit      : std_logic;
    signal theta         : unsigned(7 downto 0);

    type env_state_t is (S_ATTACK, S_DECAY, S_SUSTAIN, S_RELEASE, S_OFF);
    signal env_state    : env_state_t;
    signal env_cnt      : unsigned(8 downto 0);
    signal env_level    : unsigned(11 downto 0);
    signal env_rate_cnt : unsigned(7 downto 0);

    signal log_sin_val  : unsigned(11 downto 0);
    signal level        : unsigned(12 downto 0);  -- 13-bit: [12:9]=exp, [7:0]=mantissa
    signal exp_val      : unsigned(9 downto 0);
    signal exp_shifted  : unsigned(15 downto 0);

    -- Bias so log_sin_min (352) maps to level[12:9]=9 (shift=6, max usable)
    constant LEVEL_BIAS : unsigned(11 downto 0) := to_unsigned(1952, 12);

    signal gate_reg     : std_logic;
    signal gate_prev    : std_logic;
    signal ar_reg, dr_reg, sl_reg, rr_reg : unsigned(3 downto 0);

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

    p_mod_scale : process(clk_i)
        variable mod_signed : signed(15 downto 0);
        variable idx_signed : signed(8 downto 0);
        variable prod : signed(31 downto 0);
    begin
        if rising_edge(clk_i) then
            if mod_index_reg = 0 or gate_reg = '0' then
                mod_scaled <= (others => '0');
            else
                mod_signed := signed(modulation_i);
                idx_signed := signed('0' & std_logic_vector(mod_index_reg));
                prod := resize(shift_right(mod_signed, 7), 16) * resize(idx_signed, 16);
                mod_scaled <= resize(prod, 23);
            end if;
        end if;
    end process;

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

    final_phase <= resize(phase_acc, 23) +
                   unsigned(std_logic_vector(signed(mod_scaled)));

    sign_bit <= final_phase(10);
    p_theta : process(final_phase)
    begin
        if final_phase(9) = '0' then
            theta <= final_phase(7 downto 0);
        else
            theta <= not final_phase(7 downto 0);
        end if;
    end process;

    log_sin_val <= LOG_SINE_ROM(to_integer(theta));

    p_env : process(clk_i, rst_n_i)
        variable rate_max : unsigned(7 downto 0);
        variable sustain_level : unsigned(8 downto 0);
    begin
        if rst_n_i = '0' then
            env_state    <= S_OFF;
            env_cnt      <= to_unsigned(511, 9);
            env_rate_cnt <= (others => '0');
            env_level    <= (others => '0');
        elsif rising_edge(clk_i) then
            if sample_tick_i = '1' then
                if gate_reg = '1' and gate_prev = '0' then
                    env_state    <= S_ATTACK;
                    env_cnt      <= to_unsigned(511, 9);
                    env_rate_cnt <= (others => '0');
                elsif gate_reg = '0' and gate_prev = '1' then
                    env_state    <= S_RELEASE;
                    env_rate_cnt <= (others => '0');
                end if;

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
                        sustain_level := to_unsigned(511, 9) - resize(
                            shift_left(to_unsigned(1, 9), 5) -
                            to_unsigned(to_integer(sl_reg) * 34, 9), 9);
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
                        null;
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

                env_level <= shift_left(resize(env_cnt, 12), 3);
            end if;
        end if;
    end process;

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

    p_exp : process(clk_i)
        variable exp_addr  : integer range 0 to 255;
        variable shift_amt : integer range 0 to 15;
        variable exp_out   : unsigned(9 downto 0);
    begin
        if rising_edge(clk_i) then
            if sample_tick_i = '1' then
                exp_addr  := to_integer(not level(7 downto 0));
                shift_amt := to_integer(level(12 downto 9));
                exp_out   := EXP_LUT_ROM(exp_addr);
                if shift_amt >= 15 then
                    exp_shifted <= (others => '0');
                else
                    exp_shifted <= shift_left(resize(exp_out, 16), 15 - shift_amt);
                end if;
            end if;
        end if;
    end process;

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
