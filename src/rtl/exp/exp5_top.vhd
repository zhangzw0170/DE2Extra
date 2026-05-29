-- 实验5 顶层模块：SW[17:16] 选择一段式/两段式/三段式状态机
-- LEDG8 显示检测输出z，LEDG7~0 显示输入移位寄存器（从左到右）
-- HEX6 显示当前选择的编号(1/2/3)，SW[17:16]="00"时禁用
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity exp5_top is
    port (
        clk     : in  std_logic;
        reset   : in  std_logic;
        step    : in  std_logic;
        w       : in  std_logic;
        fsm_sel : in  std_logic_vector(1 downto 0);
        ledg    : out std_logic_vector(8 downto 0);  -- LEDG8=z, LEDG7~0=移位寄存器
        ledr0   : out std_logic;                     -- LEDR0 常亮（位置对照）
        ledr1   : out std_logic;                     -- LEDR1 显示当前输入 w
        HEX6    : out std_logic_vector(6 downto 0)
    );
end exp5_top;

architecture structural of exp5_top is
    signal z1, z2, z3 : std_logic;
    signal z          : std_logic;
    signal shift_reg  : std_logic_vector(7 downto 0);
begin
    -- 三种 FSM 实例（共享 clk/reset/w）
    u_fsm_one : entity work.fsm_one
        port map (clk => step, reset => reset, w => w, z => z1);

    u_fsm_two : entity work.fsm_two
        port map (clk => step, reset => reset, w => w, z => z2);

    u_fsm_three : entity work.fsm_three
        port map (clk => step, reset => reset, w => w, z => z3);

    -- 输出选择 + HEX6 显示（组合逻辑）
    process(fsm_sel, z1, z2, z3)
    begin
        case fsm_sel is
            when "01" =>
                z    <= z1;
                HEX6 <= "1111001";  -- "1"
            when "10" =>
                z    <= z2;
                HEX6 <= "0100100";  -- "2"
            when "11" =>
                z    <= z3;
                HEX6 <= "0110000";  -- "3"
            when others =>
                z    <= '0';
                HEX6 <= "1111111";  -- blank
        end case;
    end process;

    -- LEDG8 显示检测输出
    ledg(8) <= z;

    -- 移位寄存器：从左到右移位，记录最近8次输入
    -- 新输入 w 进入 LEDG7（左端），旧数据向 LEDG0（右端）移位
    SHIFTER : process(reset, step)
    begin
        if reset = '0' then
            shift_reg <= (others => '0');
        elsif step'event and step = '1' then
            shift_reg <= w & shift_reg(7 downto 1);  -- 右移，w 从左侧进入
        end if;
    end process;

    ledg(7 downto 0) <= shift_reg;

    -- LEDR0 常亮，用于对照 LEDG 位置
    ledr0 <= '1';

    -- LEDR1 显示当前输入 w（与原实验一致）
    ledr1 <= w;
end structural;
