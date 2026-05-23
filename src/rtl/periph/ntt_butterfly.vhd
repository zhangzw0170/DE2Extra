-- ntt_butterfly.vhd — NTT butterfly: (a+b mod q, (a-b)×ω mod q)
--
-- Cooley-Tukey DIT butterfly for NTT.
-- Input: a, b, omega (twiddle factor), all 12-bit
-- Output: A = a + b mod q,  B = (a - b) × ω mod q

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity ntt_butterfly is
    port (
        clk_i   : in  std_logic;
        a_i     : in  std_logic_vector(11 downto 0);
        b_i     : in  std_logic_vector(11 downto 0);
        w_i     : in  std_logic_vector(11 downto 0);  -- twiddle factor
        a_o     : out std_logic_vector(11 downto 0);  -- A = a+b mod q
        b_o     : out std_logic_vector(11 downto 0)   -- B = (a-b)*w mod q
    );
end ntt_butterfly;

architecture rtl of ntt_butterfly is

    constant Q : integer := 3329;

    -- Pipeline
    signal a_r, b_r, w_r : std_logic_vector(11 downto 0);

    -- Stage 1 results
    signal sum_ab    : std_logic_vector(12 downto 0);  -- a+b, 13-bit (max 3328+3328=6656)
    signal diff_ab   : std_logic_vector(12 downto 0);  -- a-b, may be negative
    signal diff_pos  : std_logic_vector(11 downto 0);  -- (a-b) mod q
    signal diff_corrected : std_logic_vector(11 downto 0);

    -- Modulo multiplier for B
    signal modmul_a   : std_logic_vector(11 downto 0);
    signal modmul_b   : std_logic_vector(11 downto 0);
    signal modmul_q   : std_logic_vector(11 downto 0);

    component ntt_modmul is
        port (
            clk_i : in  std_logic;
            a_i   : in  std_logic_vector(11 downto 0);
            b_i   : in  std_logic_vector(11 downto 0);
            q_o   : out std_logic_vector(11 downto 0)
        );
    end component;

begin

    -- ═══════════════════════════════════════════════════════════
    -- Stage 0: Register inputs
    -- ═══════════════════════════════════════════════════════════
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            a_r <= a_i;
            b_r <= b_i;
            w_r <= w_i;
        end if;
    end process;

    -- ═══════════════════════════════════════════════════════════
    -- Stage 1: A = a + b mod q
    -- ═══════════════════════════════════════════════════════════
    process(clk_i)
        variable sum_val  : unsigned(12 downto 0);
        variable diff_val : signed(12 downto 0);
    begin
        if rising_edge(clk_i) then
            -- Sum: a + b, reduce mod q
            sum_val := unsigned('0' & a_r) + unsigned('0' & b_r);
            if sum_val >= to_unsigned(Q, 13) then
                sum_ab <= std_logic_vector(sum_val - to_unsigned(Q, 13));
            else
                sum_ab <= std_logic_vector(sum_val);
            end if;

            -- Difference: a - b, reduce mod q
            diff_val := signed('0' & a_r) - signed('0' & b_r);
            if diff_val < 0 then
                diff_corrected <= std_logic_vector(unsigned(diff_val(11 downto 0)) + to_unsigned(Q, 12));
            else
                diff_corrected <= std_logic_vector(diff_val(11 downto 0));
            end if;
        end if;
    end process;

    modmul_a <= diff_corrected;
    modmul_b <= w_r;

    -- ═══════════════════════════════════════════════════════════
    -- Stage 2-5: B = (a-b) × ω mod q (via ntt_modmul pipeline)
    -- ═══════════════════════════════════════════════════════════
    u_modmul : ntt_modmul
    port map (
        clk_i => clk_i,
        a_i   => modmul_a,
        b_i   => modmul_b,
        q_o   => modmul_q
    );

    -- Output
    a_o <= sum_ab(11 downto 0);
    b_o <= modmul_q;

end rtl;
