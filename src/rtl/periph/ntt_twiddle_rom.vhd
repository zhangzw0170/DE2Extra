-- ntt_twiddle_rom.vhd — Twiddle factor ROM for NTT (q=3329, n=256)
--
-- Stores pre-computed ω^k mod 3329 for all 8 SDF stages.
-- Stage s: 256/(2^(s+1)) unique twiddle factors.
-- Primitive root: ζ = 17

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity ntt_twiddle_rom is
    port (
        clk_i     : in  std_logic;
        stage_i   : in  std_logic_vector(2 downto 0);  -- 0-7
        addr_i    : in  std_logic_vector(7 downto 0);  -- 0-128
        data_o    : out std_logic_vector(11 downto 0)  -- ω^k mod 3329
    );
end ntt_twiddle_rom;

architecture rtl of ntt_twiddle_rom is

    constant Q   : integer := 3329;
    constant ZETA : integer := 17;  -- primitive 256-th root of unity mod 3329

    -- ROM depth: 8 stages × max 128 entries = 1024 entries × 12-bit
    type rom_t is array (0 to 1023) of std_logic_vector(11 downto 0);
    signal rom : rom_t := (others => (others => '0'));

    -- Compute combined address: stage * 128 + addr
    signal combined_addr : integer range 0 to 1023;

begin

    combined_addr <= to_integer(unsigned(stage_i)) * 128 + to_integer(unsigned(addr_i));

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            data_o <= rom(combined_addr);
        end if;
    end process;

    -- ROM contents to be filled by Python script from FFT project data
    -- Stage 0 (128 entries):  ω = 17^128 mod 3329
    -- Stage 1 (64 entries):   ω = 17^64 mod 3329
    -- ...
    -- Stage 7 (1 entry):      ω = 17^1 mod 3329

end rtl;
