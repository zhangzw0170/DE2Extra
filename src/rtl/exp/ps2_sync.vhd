-- PS/2时钟同步器
-- 2级触发器同步PS2_CLK和PS2_DAT，检测PS2_CLK下降沿
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity exp8_ps2_sync is
    port (
        clk      : in  std_logic;
        ps2_clk  : in  std_logic;
        ps2_dat  : in  std_logic;
        clk_fall : out std_logic;   -- PS2_CLK下降沿脉冲
        dat_sync : out std_logic    -- 同步后的数据
    );
end exp8_ps2_sync;

architecture rtl of exp8_ps2_sync is
    signal clk_buf : std_logic_vector(2 downto 0) := "111";
    signal dat_buf : std_logic_vector(1 downto 0) := "11";
begin
    -- 2级触发器同步 + 第3级用于边沿检测
    process(clk)
    begin
        if clk'event and clk = '1' then
            clk_buf <= clk_buf(1 downto 0) & ps2_clk;
            dat_buf <= dat_buf(0) & ps2_dat;
        end if;
    end process;

    -- 下降沿检测：前一级为1，当前级为0
    clk_fall <= '1' when clk_buf(2) = '1' and clk_buf(1) = '0' else '0';
    dat_sync <= dat_buf(1);
end rtl;
