-- 实验1：3-8译码器 —— FOR循环语句实现
-- 功能：与deco138_gate功能相同，使用FOR循环+条件判断实现译码输出
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity deco138_for is
    port (
        A, B, C   : in  std_logic;
        G1        : in  std_logic;
        G2A, G2B  : in  std_logic;
        Y         : out std_logic_vector(7 downto 0)
    );
end deco138_for;

architecture behavioral of deco138_for is
    signal indata : std_logic_vector(2 downto 0);
    signal temp   : std_logic_vector(7 downto 0);
begin
    indata <= C & B & A;

    process(indata, G1, G2A, G2B)
        variable addr : integer range 0 to 7;
    begin
        addr := 0;
        if indata(0) = '1' then addr := addr + 1; end if;
        if indata(1) = '1' then addr := addr + 2; end if;
        if indata(2) = '1' then addr := addr + 4; end if;

        -- 默认全1（无效）
        temp <= (others => '1');

        if G1 = '1' and G2A = '0' and G2B = '0' then
            for i in 0 to 7 loop
                if i = addr then
                    temp(i) <= '0';
                end if;
            end loop;
        end if;

        Y <= temp;
    end process;
end behavioral;
