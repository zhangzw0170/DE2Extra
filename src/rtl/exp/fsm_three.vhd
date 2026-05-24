-- 实验5：序列检测器 —— 三段式状态机
-- 进程REG：同步时序逻辑（状态转移）
-- 进程COM：组合逻辑（次态）
-- 进程OUT：同步输出逻辑（寄存器输出，消除毛刺）
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity fsm_three is
    port (
        clk, reset : in  std_logic;
        w          : in  std_logic;
        z          : out std_logic
    );
end fsm_three;

architecture behavioral of fsm_three is
    type states is (s0, s1_0, s2_0, s3_0, s1_1, s2_1, s3_1);
    signal current_state, next_state : states;
    signal z_reg : std_logic;
begin
    -- 时序逻辑进程：状态寄存器
    REG : process(reset, clk)
    begin
        if reset = '0' then
            current_state <= s0;
        elsif clk'event and clk = '1' then
            current_state <= next_state;
        end if;
    end process;

    -- 组合逻辑进程：次态逻辑
    COM : process(current_state, w)
    begin
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
                if w = '0' then next_state <= s3_0;
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
                if w = '1' then next_state <= s3_1;
                else next_state <= s1_0;
                end if;
        end case;
    end process;

    -- 同步输出进程：寄存器输出
    OUT_PROC : process(reset, clk)
    begin
        if reset = '0' then
            z_reg <= '0';
        elsif clk'event and clk = '1' then
            case current_state is
                when s3_0 => if w = '0' then z_reg <= '1'; else z_reg <= '0'; end if;
                when s3_1 => if w = '1' then z_reg <= '1'; else z_reg <= '0'; end if;
                when others => z_reg <= '0';
            end case;
        end if;
    end process;

    z <= z_reg;
end behavioral;
