-- 实验5：序列检测器 —— 一段式状态机
-- 检测输入w中连续4个0或连续4个1，检测到时输出z=1
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity fsm_one is
    port (
        clk, reset : in  std_logic;
        w          : in  std_logic;
        z          : out std_logic
    );
end fsm_one;

architecture behavioral of fsm_one is
    type states is (s0, s1_0, s2_0, s3_0, s1_1, s2_1, s3_1);
    signal state : states := s0;
begin
    process(clk, reset)
    begin
        if reset = '0' then
            state <= s0;
            z <= '0';
        elsif clk'event and clk = '1' then
            case state is
                when s0 =>
                    z <= '0';
                    if w = '0' then state <= s1_0;
                    else state <= s1_1;
                    end if;
                when s1_0 =>
                    z <= '0';
                    if w = '0' then state <= s2_0;
                    else state <= s1_1;
                    end if;
                when s2_0 =>
                    z <= '0';
                    if w = '0' then state <= s3_0;
                    else state <= s1_1;
                    end if;
                when s3_0 =>
                    if w = '0' then z <= '1'; state <= s3_0;
                    else z <= '0'; state <= s1_1;
                    end if;
                when s1_1 =>
                    z <= '0';
                    if w = '1' then state <= s2_1;
                    else state <= s1_0;
                    end if;
                when s2_1 =>
                    z <= '0';
                    if w = '1' then state <= s3_1;
                    else state <= s1_0;
                    end if;
                when s3_1 =>
                    if w = '1' then z <= '1'; state <= s3_1;
                    else z <= '0'; state <= s1_0;
                    end if;
            end case;
        end if;
    end process;
end behavioral;
