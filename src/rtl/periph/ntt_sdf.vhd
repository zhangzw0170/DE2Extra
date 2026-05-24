-- ntt_sdf.vhd — NTT accelerator for DE2Extra (synthesizable rewrite)
--
-- N=256, q=3329 (ML-KEM-512), g=17 (primitive 256th root of unity).
-- Unified DIF Cooley-Tukey butterfly: (A+B, (A-B)*w), stages 7→0.
-- Output is bit-reversed; software does bit-reversal for natural-order results.
--
-- INTT: same engine, inverse twiddles (q-g^{128-k}), then N^{-1} scaling.
--
-- Constants (verified by ntt_verify.py):
--   Barrett constant = 5039 = floor(2^24/3329)
--   N^{-1} mod q = 3316  (256*3316 mod 3329 = 1)
--   g^128 mod q = 3328 = q-1 (used for inverse twiddle formula)
--
-- Register map (byte offsets, 32-bit Wishbone):
--   0x000-0x3FF  R/W  Data [0..255], 12-bit (word-indexed by adr[9:2])
--   0x400        W    Control: bit0=start, bit1=dir (0=NTT, 1=INTT)
--   0x404        R    Status:  bit0=busy, bit1=done (sticky, cleared on start)
--   0x408        R    Cycle count [31:0]

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ntt_sdf is
    port (
        clk_i     : in  std_logic;
        rst_n_i   : in  std_logic;

        -- Wishbone slave (32-bit)
        wb_adr_i  : in  std_logic_vector(11 downto 0);
        wb_dat_i  : in  std_logic_vector(31 downto 0);
        wb_dat_o  : out std_logic_vector(31 downto 0);
        wb_we_i   : in  std_logic;
        wb_stb_i  : in  std_logic;
        wb_ack_o  : out std_logic
    );
end entity ntt_sdf;

architecture rtl of ntt_sdf is

    -- ── Constants ────────────────────────────────────────────────
    constant MODULUS_C  : unsigned(11 downto 0) := to_unsigned(3329, 12);
    constant BARRETT_C  : unsigned(12 downto 0) := to_unsigned(5039, 13);
    constant N_INV_C    : unsigned(11 downto 0) := to_unsigned(3316, 12);

    -- ── Twiddle ROM ─────────────────────────────────────────────
    -- tw(k) = 17^k mod 3329, k = 0..127
    type tw_array_t is array(0 to 127) of unsigned(11 downto 0);

    function gen_tw return tw_array_t is
        variable t : tw_array_t;
        variable v : natural;
    begin
        v := 1;
        for k in 0 to 127 loop
            t(k) := to_unsigned(v mod 3329, 12);
            v := (v * 17) mod 3329;
        end loop;
        return t;
    end function;

    constant TW : tw_array_t := gen_tw;

    -- ── Half-value LUT (replaces 2**stage) ──────────────────────
    type half_array_t is array(0 to 7) of unsigned(7 downto 0);
    constant HALF_LUT : half_array_t := (
        0 => to_unsigned(1, 8),
        1 => to_unsigned(2, 8),
        2 => to_unsigned(4, 8),
        3 => to_unsigned(8, 8),
        4 => to_unsigned(16, 8),
        5 => to_unsigned(32, 8),
        6 => to_unsigned(64, 8),
        7 => to_unsigned(128, 8)
    );

    -- ── Data buffer ─────────────────────────────────────────────
    type buf_t is array(0 to 255) of unsigned(11 downto 0);
    signal buf : buf_t := (others => (others => '0'));

    -- ── Control / Status ────────────────────────────────────────
    signal ctrl_dir    : std_logic;
    signal reg_start   : std_logic;
    signal status_busy : std_logic := '0';
    signal status_done : std_logic := '0';
    signal cycle_cnt   : unsigned(31 downto 0) := (others => '0');

    type state_t is (S_IDLE, S_BF, S_STAGE_END, S_SCALE, S_DONE);
    signal state : state_t := S_IDLE;
    signal stage : unsigned(2 downto 0) := (others => '0');
    signal elem  : unsigned(6 downto 0) := (others => '0');

    signal ack : std_logic := '0';

    -- Barrett reduction: (a * b) mod 3329
    -- Barrett: q_est = (prod * MU) >> 24, r = prod - q_est * Q
    function barrett_reduce(prod : unsigned(23 downto 0)) return unsigned is
        variable prod_mu : unsigned(36 downto 0);
        variable q_est   : unsigned(12 downto 0);
        variable q_prod  : unsigned(24 downto 0);
        variable r       : unsigned(23 downto 0);
    begin
        prod_mu := prod * BARRETT_C;               -- 24 × 13 = 37 bits
        q_est   := prod_mu(35 downto 23);           -- >> 23, 13-bit
        q_prod  := q_est * resize(MODULUS_C, 12);   -- 13 × 12 = 25 bits
        r := prod - q_prod(23 downto 0);
        if r >= resize(MODULUS_C, 24) then
            r := r - resize(MODULUS_C, 24);
        end if;
        return r(11 downto 0);
    end function;

begin

    -- ================================================================
    -- Wishbone interface + NTT engine (single process to avoid multi-driver on buf)
    -- ================================================================
    process(clk_i)
        variable widx    : unsigned(7 downto 0);
        variable half    : unsigned(7 downto 0);
        variable b127    : unsigned(6 downto 0);
        variable grp     : unsigned(6 downto 0);
        variable idx     : unsigned(6 downto 0);
        variable top_val : unsigned(7 downto 0);
        variable a_val   : unsigned(11 downto 0);
        variable b_val   : unsigned(11 downto 0);
        variable tw_idx_v: unsigned(6 downto 0);
        variable tw_val  : unsigned(11 downto 0);
        variable sum_v   : unsigned(12 downto 0);
        variable dif_v   : unsigned(12 downto 0);
        variable prod_v  : unsigned(23 downto 0);
        variable s_elem  : integer range 0 to 255;
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                reg_start <= '0'; status_done <= '0';
                status_busy <= '0'; state <= S_IDLE;
            else
                reg_start <= '0';

                -- Wishbone control/data writes (blocked while engine is busy)
                if wb_stb_i = '1' and wb_we_i = '1' and status_busy = '0' then
                    if unsigned(wb_adr_i) = x"400" then
                        ctrl_dir <= wb_dat_i(1);
                        reg_start <= wb_dat_i(0);
                        if wb_dat_i(0) = '1' then status_done <= '0'; end if;
                    elsif unsigned(wb_adr_i(11 downto 10)) = 0 then
                        widx := unsigned(wb_adr_i(9 downto 2));
                        if widx < 256 then
                            buf(to_integer(widx)) <= unsigned(wb_dat_i(11 downto 0));
                        end if;
                    end if;
                end if;

                -- NTT engine state machine
                case state is
                    when S_IDLE =>
                        if reg_start = '1' then
                            state <= S_BF; status_busy <= '1';
                            stage <= "111"; elem <= (others => '0');
                            cycle_cnt <= (others => '0');
                        end if;

                    when S_BF =>
                        cycle_cnt <= cycle_cnt + 1;
                        half := HALF_LUT(to_integer(stage));
                        b127 := elem;

                        case to_integer(stage) is
                            when 0 => idx := b127(6 downto 0); grp := "0000000";
                            when 1 => idx := "000000" & b127(0 downto 0); grp := "0" & b127(6 downto 1);
                            when 2 => idx := "00000" & b127(1 downto 0); grp := "00" & b127(6 downto 2);
                            when 3 => idx := "0000" & b127(2 downto 0); grp := "000" & b127(6 downto 3);
                            when 4 => idx := "000" & b127(3 downto 0); grp := "0000" & b127(6 downto 4);
                            when 5 => idx := "00" & b127(4 downto 0); grp := "00000" & b127(6 downto 5);
                            when 6 => idx := "0" & b127(5 downto 0); grp := "000000" & b127(6 downto 6);
                            when 7 => idx := b127; grp := "0000000";
                            when others => idx := b127; grp := "0000000";
                        end case;

                        top_val := resize(grp * half & '0', 8) + resize(idx, 8);

                        s_elem := to_integer(top_val);
                        a_val := buf(s_elem);
                        b_val := buf(s_elem + to_integer(half));

                        case to_integer(stage) is
                            when 0 => tw_idx_v := idx(0 downto 0) & "000000";
                            when 1 => tw_idx_v := idx(1 downto 0) & "00000";
                            when 2 => tw_idx_v := idx(2 downto 0) & "0000";
                            when 3 => tw_idx_v := idx(3 downto 0) & "000";
                            when 4 => tw_idx_v := idx(4 downto 0) & "00";
                            when 5 => tw_idx_v := idx(5 downto 0) & "0";
                            when 6 => tw_idx_v := idx;
                            when 7 => tw_idx_v := "0000000";
                            when others => tw_idx_v := "0000000";
                        end case;

                        tw_val := TW(to_integer(tw_idx_v));
                        if ctrl_dir = '1' and tw_idx_v /= 0 then
                            tw_val := MODULUS_C - TW(to_integer(to_unsigned(128, 7) - tw_idx_v));
                        end if;

                        sum_v := resize(a_val, 13) + resize(b_val, 13);
                        if sum_v >= resize(MODULUS_C, 13) then
                            sum_v := sum_v - resize(MODULUS_C, 13);
                        end if;

                        dif_v := resize(a_val, 13) + resize(MODULUS_C, 13) - resize(b_val, 13);
                        if dif_v >= resize(MODULUS_C, 13) then
                            dif_v := dif_v - resize(MODULUS_C, 13);
                        end if;

                        prod_v := dif_v(11 downto 0) * tw_val;
                        buf(s_elem) <= sum_v(11 downto 0);
                        buf(s_elem + to_integer(half)) <= barrett_reduce(prod_v);

                        if elem < 127 then
                            elem <= elem + 1;
                        else
                            state <= S_STAGE_END;
                        end if;

                    when S_STAGE_END =>
                        cycle_cnt <= cycle_cnt + 1;
                        if stage > 0 then
                            stage <= stage - 1;
                            elem <= (others => '0');
                            state <= S_BF;
                        elsif ctrl_dir = '1' then
                            state <= S_SCALE; elem <= (others => '0');
                        else
                            state <= S_DONE;
                        end if;

                    when S_SCALE =>
                        cycle_cnt <= cycle_cnt + 1;
                        s_elem := to_integer(elem);
                        if s_elem < 256 then
                            prod_v := buf(s_elem) * N_INV_C;
                            buf(s_elem) <= barrett_reduce(prod_v);
                            elem <= elem + 1;
                        else
                            state <= S_DONE;
                        end if;

                    when S_DONE =>
                        status_busy <= '0'; status_done <= '1'; state <= S_IDLE;

                end case;
            end if;
        end if;
    end process;

    -- Read mux (combinational)
    process(all)
        variable ridx : unsigned(7 downto 0);
    begin
        wb_dat_o <= (others => '0');
        if wb_stb_i = '1' and wb_we_i = '0' then
            if unsigned(wb_adr_i) = x"404" then
                wb_dat_o(0) <= status_busy;
                wb_dat_o(1) <= status_done;
            elsif unsigned(wb_adr_i) = x"408" then
                wb_dat_o <= std_logic_vector(cycle_cnt);
            elsif unsigned(wb_adr_i(11 downto 10)) = 0 then
                ridx := unsigned(wb_adr_i(9 downto 2));
                if ridx < 256 then
                    wb_dat_o(11 downto 0) <= std_logic_vector(buf(to_integer(ridx)));
                end if;
            end if;
        end if;
    end process;

    -- Ack
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then ack <= '0'; else ack <= wb_stb_i and not ack; end if;
        end if;
    end process;
    wb_ack_o <= ack;

end architecture rtl;
