-- 实验5：序列检测器 —— 两段式状态机
-- 进程REG：同步时序逻辑（状态转移 + 输出寄存）
-- 进程COM：组合逻辑（次态 + 组合输出）
-- 注意：z 经过寄存器打一拍，与一段式/三段式时序一致（均需4拍触发）
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity fsm_two is
    port (
        clk, reset : in  std_logic;
        w          : in  std_logic;
        z          : out std_logic
    );
end fsm_two;

architecture behavioral of fsm_two is
    type states is (s0, s1_0, s2_0, s3_0, s1_1, s2_1, s3_1);
    signal current_state, next_state : states;
    signal z_comb : std_logic;  -- 组合输出（中间信号）
begin
    -- 时序逻辑进程：状态寄存器 + 输出寄存
    REG : process(reset, clk)
    begin
        if reset = '0' then
            current_state <= s0;
            z <= '0';
        elsif clk'event and clk = '1' then
            current_state <= next_state;
            z <= z_comb;
        end if;
    end process;

    -- 组合逻辑进程：次态逻辑 + 输出逻辑
    COM : process(current_state, w)
    begin
        z_comb <= '0';  -- 默认输出

        case current_state is
            when s0 =>
                if w = '0' then next_state <= s1_0;
                else next_state <= s1_1;
                end if;
            when s1_0 =>
                if w = '0' then next_state <= s2_0;
                else next_state <= s1_1;
                end if;
            when s2_0 =>
                if w = '0' then next_state <= s3_0;
                else next_state <= s1_1;
                end if;
            when s3_0 =>
                if w = '0' then next_state <= s3_0; z_comb <= '1';
                else next_state <= s1_1;
                end if;
            when s1_1 =>
                if w = '1' then next_state <= s2_1;
                else next_state <= s1_0;
                end if;
            when s2_1 =>
                if w = '1' then next_state <= s3_1;
                else next_state <= s1_0;
                end if;
            when s3_1 =>
                if w = '1' then next_state <= s3_1; z_comb <= '1';
                else next_state <= s1_0;
                end if;
        end case;
    end process;
end behavioral;
