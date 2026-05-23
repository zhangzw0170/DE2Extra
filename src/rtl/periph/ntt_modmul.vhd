-- ntt_modmul.vhd — Modular multiplier for NTT (q=3329)
--
-- Computes (a × b) mod 3329 using 18×18 DSP + Barrett reduction.
-- Input: 12-bit unsigned, Output: 12-bit unsigned in [0, 3328].
--
-- Barrett reduction for q=3329:
--   μ = floor(2^24 / 3329) = 5041
--   t = (a × b × μ) >> 24
--   r = (a × b) - t × 3329
--   if r >= 3329: r -= 3329

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity ntt_modmul is
    port (
        clk_i   : in  std_logic;
        a_i     : in  std_logic_vector(11 downto 0);
        b_i     : in  std_logic_vector(11 downto 0);
        q_o     : out std_logic_vector(11 downto 0)  -- a*b mod 3329
    );
end ntt_modmul;

architecture rtl of ntt_modmul is

    constant Q     : integer := 3329;
    constant MU    : integer := 5041;  -- floor(2^24 / 3329)

    -- Pipeline registers
    signal a_r, b_r : std_logic_vector(11 downto 0);
    signal prod     : std_logic_vector(23 downto 0);  -- 12×12 = 24 bit
    signal t        : std_logic_vector(23 downto 0);  -- (prod * MU) >> 24 approximation
    signal t2       : std_logic_vector(23 downto 0);  -- t * Q
    signal r        : std_logic_vector(23 downto 0);  -- prod - t2
    signal r2       : std_logic_vector(11 downto 0);

    -- DSP result (wider for Barrett intermediate)
    signal prod_mu  : std_logic_vector(35 downto 0);  -- 24 × 13 = 37 bits, keep 36

begin

    -- ═══════════════════════════════════════════════════════════
    -- Stage 0: Register inputs
    -- ═══════════════════════════════════════════════════════════
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            a_r <= a_i;
            b_r <= b_i;
        end if;
    end process;

    -- ═══════════════════════════════════════════════════════════
    -- Stage 1: 12×12 multiply → 24-bit (uses 1 DSP)
    -- ═══════════════════════════════════════════════════════════
    prod <= a_r * b_r;

    -- ═══════════════════════════════════════════════════════════
    -- Stage 2: Barrett reduction
    --   t = (prod * MU) >> 24
    --   Uses 1 more DSP for 24×13 multiply
    -- ═══════════════════════════════════════════════════════════
    prod_mu <= prod * to_unsigned(MU, 13);
    t <= prod_mu(35 downto 12);  -- shift right by 12... wait, we need >> 24

    -- Actually Barrett: t = floor(prod * MU / 2^24)
    -- prod is 24-bit, MU is 5041 ≈ 2^12.3
    -- prod * MU is 24+13 = 37 bits max. We take bits[36:24] = >> 24 = 13 bits.
    -- So t = prod_mu(36 downto 24) is 13 bits.

    -- ═══════════════════════════════════════════════════════════
    -- Stage 3: t2 = t × Q, r = prod - t2
    -- ═══════════════════════════════════════════════════════════
    process(clk_i)
        variable t_val : unsigned(12 downto 0);
        variable t2_val : unsigned(24 downto 0);
        variable r_val  : unsigned(23 downto 0);
    begin
        if rising_edge(clk_i) then
            t_val := unsigned(prod_mu(36 downto 24));  -- 13-bit t
            t2_val := t_val * to_unsigned(Q, 12);       -- 13×12 = 25 bits max
            r_val := unsigned(prod) - t2_val(23 downto 0);

            -- Conditional subtraction: if r >= Q, subtract Q
            if r_val >= to_unsigned(Q, 24) then
                r_val := r_val - to_unsigned(Q, 24);
            end if;

            r2 <= std_logic_vector(r_val(11 downto 0));
        end if;
    end process;

    q_o <= r2;

end rtl;
