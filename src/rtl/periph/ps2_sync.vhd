-- ps2_sync.vhd — PS/2 时钟同步器
-- 来源: Exp8 (已验收)
-- 2级触发器同步 PS2_CLK 和 PS2_DAT，检测 PS2_CLK 下降沿
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity ps2_sync is
    port (
        clk      : in  std_logic;
        ps2_clk  : in  std_logic;
        ps2_dat  : in  std_logic;
        clk_fall : out std_logic;   -- PS2_CLK 下降沿脉冲
        dat_sync : out std_logic    -- 同步后的数据
    );
end ps2_sync;

architecture rtl of ps2_sync is
    signal clk_buf : std_logic_vector(2 downto 0) := "111";
    signal dat_buf : std_logic_vector(1 downto 0) := "11";
begin
    process(clk)
    begin
        if rising_edge(clk) then
            clk_buf <= clk_buf(1 downto 0) & ps2_clk;
            dat_buf <= dat_buf(0) & ps2_dat;
        end if;
    end process;

    clk_fall <= '1' when clk_buf(2) = '1' and clk_buf(1) = '0' else '0';
    dat_sync <= dat_buf(1);
end rtl;
