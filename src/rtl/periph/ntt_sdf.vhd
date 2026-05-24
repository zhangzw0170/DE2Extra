-- ntt_sdf.vhd — NTT accelerator for DE2Extra
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

    constant MODULUS_C : natural := 3329;
    constant BARRETT_C : natural := 5039;
    constant N_INV_C   : natural := 3316;

    -- tw(k) = 17^k mod 3329, k = 0..127
    type tw_array_t is array(0 to 127) of natural;
    function gen_tw return tw_array_t is
        variable t : tw_array_t; variable v : natural;
    begin
        v := 1;
        for k in 0 to 127 loop t(k) := v; v := (v * 17) mod MODULUS_C; end loop;
        return t;
    end function;
    constant TW : tw_array_t := gen_tw;

    -- Data buffer: 256 x 12-bit
    type buf_t is array(0 to 255) of std_logic_vector(11 downto 0);
    signal buf : buf_t := (others => (others => '0'));

    signal ctrl_dir    : std_logic;
    signal reg_start   : std_logic;
    signal status_busy : std_logic := '0';
    signal status_done : std_logic := '0';
    signal cycle_cnt   : unsigned(31 downto 0) := (others => '0');

    type state_t is (S_IDLE, S_BF, S_STAGE_END, S_SCALE, S_DONE);
    signal state : state_t := S_IDLE;
    signal stage : natural range 0 to 7;
    signal elem  : natural range 0 to 127;

    signal ack : std_logic := '0';

begin

    -- ================================================================
    -- Wishbone interface
    -- ================================================================
    process(clk_i)
        variable widx : natural;
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                reg_start <= '0'; status_done <= '0';
            else
                reg_start <= '0';
                if wb_stb_i = '1' and wb_we_i = '1' then
                    if wb_adr_i = x"400" then
                        ctrl_dir <= wb_dat_i(1);
                        reg_start <= wb_dat_i(0);
                        if wb_dat_i(0) = '1' then status_done <= '0'; end if;
                    elsif unsigned(wb_adr_i(11 downto 10)) = 0 then
                        widx := to_integer(unsigned(wb_adr_i(9 downto 2)));
                        if widx < 256 then buf(widx) <= wb_dat_i(11 downto 0); end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Read mux
    process(all)
        variable ridx : natural;
    begin
        wb_dat_o <= (others => '0');
        if wb_stb_i = '1' and wb_we_i = '0' then
            if wb_adr_i = x"404" then
                wb_dat_o(0) <= status_busy;
                wb_dat_o(1) <= status_done;
            elsif wb_adr_i = x"408" then
                wb_dat_o <= std_logic_vector(cycle_cnt);
            elsif unsigned(wb_adr_i(11 downto 10)) = 0 then
                ridx := to_integer(unsigned(wb_adr_i(9 downto 2)));
                if ridx < 256 then wb_dat_o <= x"00000" & buf(ridx); end if;
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

    -- ================================================================
    -- DIF NTT Engine — stages 7→0, butterfly (A+B, (A-B)*w)
    --
    -- Stage s: half = 2^s
    --   128 butterflies, b = 0..127:
    --     grp = b/half, idx = b mod half
    --     top = grp*2*half + idx,  bot = top + half
    --     tw_idx = idx * (128/half)
    --     tw_val = TW(tw_idx),  or q - TW(128-tw_idx) for INTT
    --     sum = (a + b) mod q
    --     dif = (a - b) mod q
    --     bot' = barrett(dif * tw_val)
    -- ================================================================
    process(clk_i)
        variable half     : natural;
        variable top, bot : natural range 0 to 255;
        variable a, bv    : natural;
        variable tw_idx   : natural range 0 to 127;
        variable tw_val   : natural;
        variable sv, dv   : natural;
        variable prod     : natural;
        variable qe, rv   : natural;
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                state <= S_IDLE; status_busy <= '0';
            else
                case state is
                    when S_IDLE =>
                        if reg_start = '1' then
                            state <= S_BF; status_busy <= '1';
                            stage <= 7; elem <= 0; cycle_cnt <= (others => '0');
                        end if;

                    when S_BF =>
                        cycle_cnt <= cycle_cnt + 1;
                        half := 2 ** stage;

                        top := (elem / half) * 2 * half + (elem mod half);
                        bot := top + half;

                        a := to_integer(unsigned(buf(top)));
                        bv := to_integer(unsigned(buf(bot)));

                        -- Twiddle
                        tw_idx := (elem mod half) * (128 / half);
                        tw_val := TW(tw_idx);
                        if ctrl_dir = '1' and tw_idx > 0 then
                            tw_val := MODULUS_C - TW(128 - tw_idx);
                        end if;

                        -- Sum
                        sv := a + bv;
                        if sv >= MODULUS_C then sv := sv - MODULUS_C; end if;

                        -- Diff
                        dv := a + MODULUS_C - bv;
                        if dv >= MODULUS_C then dv := dv - MODULUS_C; end if;

                        -- Barrett: dv * tw_val mod q
                        prod := dv * tw_val;
                        qe := (prod * BARRETT_C) / 16777216;
                        rv := prod - qe * MODULUS_C;
                        if rv >= MODULUS_C then rv := rv - MODULUS_C; end if;

                        buf(top) <= std_logic_vector(to_unsigned(sv, 12));
                        buf(bot) <= std_logic_vector(to_unsigned(rv, 12));

                        if elem < 127 then
                            elem <= elem + 1;
                        else
                            state <= S_STAGE_END;
                        end if;

                    when S_STAGE_END =>
                        cycle_cnt <= cycle_cnt + 1;
                        if stage > 0 then
                            stage <= stage - 1;
                            elem <= 0;
                            state <= S_BF;
                        elsif ctrl_dir = '1' then
                            state <= S_SCALE; elem <= 0;
                        else
                            state <= S_DONE;
                        end if;

                    when S_SCALE =>
                        cycle_cnt <= cycle_cnt + 1;
                        if elem < 256 then
                            prod := to_integer(unsigned(buf(elem))) * N_INV_C;
                            qe := (prod * BARRETT_C) / 16777216;
                            rv := prod - qe * MODULUS_C;
                            if rv >= MODULUS_C then rv := rv - MODULUS_C; end if;
                            buf(elem) <= std_logic_vector(to_unsigned(rv, 12));
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

end architecture rtl;
