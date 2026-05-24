-- 实验3：7段译码器
-- 输入A0,A1,A2: 当取值000~010时显示H,E,L,O，其他显示空格
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity seg_decoder is
    port (
        A0, A1, A2 : in  std_logic;
        seg        : out std_logic_vector(6 downto 0)  -- 共阳极段码 gfedcba
    );
end seg_decoder;

architecture behavioral of seg_decoder is
    signal input_val : std_logic_vector(2 downto 0);
begin
    input_val <= A2 & A1 & A0;

    process(input_val)
    begin
        case input_val is
            when "000" => seg <= "0001001";   -- H: 显示段b,c,e,f,g
            when "001" => seg <= "0000110";   -- E: 显示段a,d,e,f,g
            when "010" => seg <= "1000111";   -- L: 显示段d,e,f
            when "011" => seg <= "1000000";   -- O: 显示段a,b,c,d,e,f
            when others => seg <= "1111111";  -- 空格: 全灭
        end case;
    end process;
end behavioral;
