-- 实验12：简单CPU芯片设计（按实验指导书实现）
-- 架构：单累加器 AC + PC + IR + MAR + MDR，多周期 FSM
-- 指令格式：[opcode:8][address:8]，共16位
-- 指令集：ADD(00), STORE(01), LOAD(02), JUMP(03), JNEG(04)
-- 支持：自动运行 + 单步执行两种模式
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity simple_cpu is
    generic (
        CLK_DIV_BITS : integer := 22   -- 时钟分频位数，2^22≈12Hz（硬件）
    );
    port (
        CLOCK_50 : in  std_logic;
        KEY0_N   : in  std_logic;                       -- 复位（低有效）
        KEY1_N   : in  std_logic;                       -- 单步（下降沿触发一个FSM状态）
        KEY2_N   : in  std_logic;                       -- 切换自动/手动模式
        SW16     : in  std_logic;                       -- LCD详细模式(1)/简单模式(0)
        LEDR     : out std_logic_vector(17 downto 0);    -- [7:0]=AC低8位, [16]=LCD详细模式, [17]=自动运行指示
        LEDG     : out std_logic_vector(7 downto 0);     -- KEY1步进次数（二进制，KEY0清零）
        HEX0     : out std_logic_vector(6 downto 0);     -- PC低4位
        HEX1     : out std_logic_vector(6 downto 0);     -- AC[3:0]
        HEX2     : out std_logic_vector(6 downto 0);     -- AC[7:4]
        HEX3     : out std_logic_vector(6 downto 0);     -- 当前操作码
        HEX4     : out std_logic_vector(6 downto 0);     -- 未使用（灭）
        HEX5     : out std_logic_vector(6 downto 0);     -- 未使用（灭）
        HEX6     : out std_logic_vector(6 downto 0);     -- 未使用（灭）
        HEX7     : out std_logic_vector(6 downto 0);     -- 未使用（灭）
        LCD_DATA : out std_logic_vector(7 downto 0);     -- LCD数据
        LCD_RS   : out std_logic;                        -- LCD寄存器选择
        LCD_RW   : out std_logic;                        -- LCD读写
        LCD_EN   : out std_logic;                        -- LCD使能
        LCD_ON   : out std_logic;                        -- LCD电源
        LCD_BLON : out std_logic;                        -- LCD背光
        FSM_ID   : buffer std_logic_vector(3 downto 0);   -- 当前FSM状态编码（供LCD显示）
        PC_O     : out std_logic_vector(7 downto 0);
        AC_O     : out std_logic_vector(15 downto 0);
        IR_O     : out std_logic_vector(15 downto 0);
        STEP_CNT_O : out std_logic_vector(7 downto 0);
        AUTO_RUN_O : out std_logic;
        DETAIL_O   : out std_logic;
        FSM_ID_O   : out std_logic_vector(3 downto 0)
    );
end simple_cpu;

architecture behavioral of simple_cpu is
    -- ===== 按键消抖与边沿检测 =====
    constant DEBOUNCE_MAX : integer := 250000;  -- 50MHz下约5ms
    -- KEY0 消抖（用于清空步进计数器）
    signal key0_meta : std_logic := '1';
    signal key0_sync : std_logic := '1';
    signal key0_db   : std_logic := '1';
    signal key0_prev : std_logic := '1';
    signal key0_cnt  : integer range 0 to DEBOUNCE_MAX-1 := 0;
    -- KEY1 消抖（2级同步器 + 计数器）
    signal key1_meta : std_logic := '1';
    signal key1_sync : std_logic := '1';
    signal key1_db   : std_logic := '1';
    signal key1_prev : std_logic := '1';
    signal key1_cnt  : integer range 0 to DEBOUNCE_MAX-1 := 0;
    -- KEY2 消抖
    signal key2_meta : std_logic := '1';
    signal key2_sync : std_logic := '1';
    signal key2_db   : std_logic := '1';
    signal key2_prev : std_logic := '1';
    signal key2_cnt  : integer range 0 to DEBOUNCE_MAX-1 := 0;

    -- KEY1 步进次数计数器
    signal step_cnt : std_logic_vector(7 downto 0) := (others => '0');

    -- ===== 运行模式 =====
    signal auto_run    : std_logic := '0';   -- 自动运行模式
    signal step_pulse  : std_logic := '0';   -- 单步脉冲
    signal ce          : std_logic := '0';   -- FSM时钟使能

    -- ===== 时钟分频 =====
    constant CLK_DIV : integer := 2**CLK_DIV_BITS;
    signal clk_cnt   : integer range 0 to CLK_DIV-1 := 0;
    signal div_ce    : std_logic := '0';     -- 分频后的时钟使能

    -- ===== 存储器 256×16位（指令与数据共享） =====
    type mem_array is array(0 to 255) of std_logic_vector(15 downto 0);
    signal mem : mem_array := (
        -- 程序区：A = B + C（含全部5条指令演示）
        0  => x"0211",  -- LOAD B      (AC = MEM[0x11] = 3)
        1  => x"0012",  -- ADD  C      (AC = AC + MEM[0x12] = 8)
        2  => x"0110",  -- STORE A     (MEM[0x10] = AC = 8)
        3  => x"0213",  -- LOAD D      (AC = MEM[0x13] = -1)
        4  => x"0406",  -- JNEG 6      (AC<0, 跳转到地址6)
        5  => x"0307",  -- JUMP 7      (死代码，JNEG应跳过)
        6  => x"0211",  -- LOAD B      (JNEG跳到这里, AC = 3)
        7  => x"0012",  -- ADD  C      (AC = 3 + 5 = 8)
        8  => x"0110",  -- STORE A     (MEM[0x10] = 8)
        9  => x"0309",  -- JUMP 9      (自循环)
        -- 数据区
        16 => x"0000",  -- A = 0（结果）
        17 => x"0003",  -- B = 3
        18 => x"0005",  -- C = 5
        19 => x"FFFF",  -- D = -1（负数，用于测试JNEG）
        others => (others => '0')
    );

    -- ===== 处理器寄存器 =====
    signal ac  : std_logic_vector(15 downto 0) := (others => '0');
    signal pc  : std_logic_vector(7 downto 0)  := (others => '0');
    signal ir  : std_logic_vector(15 downto 0) := (others => '0');
    signal mar : std_logic_vector(7 downto 0)  := (others => '0');
    signal mdr : std_logic_vector(15 downto 0) := (others => '0');

    -- ===== 控制单元状态机 =====
    type state_type is (
        S_FETCH1, S_FETCH2, S_FETCH3, S_DECODE,
        S_ADD1, S_ADD2, S_ADD3,
        S_STORE1, S_STORE2,
        S_LOAD1, S_LOAD2, S_LOAD3,
        S_JUMP, S_JNEG
    );
    signal state : state_type := S_FETCH1;

    -- ===== LCD 显示组件 =====
    component lcd_display is
        port (
            CLOCK_50 : in  std_logic;
            rst_n    : in  std_logic;
            trigger  : in  std_logic;
            detail   : in  std_logic;
            fsm_id   : in  std_logic_vector(3 downto 0);
            pc       : in  std_logic_vector(7 downto 0);
            ac       : in  std_logic_vector(15 downto 0);
            ir       : in  std_logic_vector(15 downto 0);
            LCD_DATA : out std_logic_vector(7 downto 0);
            LCD_RS   : out std_logic;
            LCD_RW   : out std_logic;
            LCD_EN   : out std_logic;
            LCD_ON   : out std_logic;
            LCD_BLON : out std_logic
        );
    end component;

    -- ===== 7段译码 =====
    function to_7seg(val : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        case val is
            when "0000" => return "1000000"; when "0001" => return "1111001";
            when "0010" => return "0100100"; when "0011" => return "0110000";
            when "0100" => return "0011001"; when "0101" => return "0010010";
            when "0110" => return "0000010"; when "0111" => return "1111000";
            when "1000" => return "0000000"; when "1001" => return "0010000";
            when "1010" => return "0001000"; when "1011" => return "0000011";
            when "1100" => return "1000110"; when "1101" => return "0100001";
            when "1110" => return "0000110"; when "1111" => return "0001110";
            when others => return "1111111";
        end case;
    end function;
begin
    -- ===== KEY0 消抖 =====
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            key0_meta <= KEY0_N;
            key0_sync <= key0_meta;
            if key0_sync = key0_db then
                key0_cnt <= 0;
            elsif key0_cnt = DEBOUNCE_MAX-1 then
                key0_db <= key0_sync;
                key0_cnt <= 0;
            else
                key0_cnt <= key0_cnt + 1;
            end if;
            key0_prev <= key0_db;
        end if;
    end process;

    -- ===== KEY1 步进次数计数，KEY0 按下时清零 =====
    process(CLOCK_50, KEY0_N)
    begin
        if KEY0_N = '0' then
            step_cnt <= (others => '0');
        elsif CLOCK_50'event and CLOCK_50 = '1' then
            if key1_prev = '1' and key1_db = '0' then
                step_cnt <= step_cnt + 1;
            end if;
        end if;
    end process;

    LEDG <= step_cnt;

    -- ===== KEY1 消抖：2级同步器 + 计数器（同步输入稳定10ms后更新消抖输出）=====
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            key1_meta <= KEY1_N;       -- FF1
            key1_sync <= key1_meta;    -- FF2
            if key1_sync = key1_db then
                key1_cnt <= 0;         -- 已同步，无变化
            elsif key1_cnt = DEBOUNCE_MAX-1 then
                key1_db <= key1_sync;   -- 稳定10ms，接受变化
                key1_cnt <= 0;
            else
                key1_cnt <= key1_cnt + 1;
            end if;
            key1_prev <= key1_db;
        end if;
    end process;
    step_pulse <= key1_prev and (not key1_db);  -- 下降沿：严格一个时钟周期

    -- ===== KEY2 消抖 =====
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            key2_meta <= KEY2_N;
            key2_sync <= key2_meta;
            if key2_sync = key2_db then
                key2_cnt <= 0;
            elsif key2_cnt = DEBOUNCE_MAX-1 then
                key2_db <= key2_sync;
                key2_cnt <= 0;
            else
                key2_cnt <= key2_cnt + 1;
            end if;
            key2_prev <= key2_db;
        end if;
    end process;

    -- ===== 模式切换（KEY2 下降沿翻转 auto_run） =====
    process(CLOCK_50, KEY0_N)
    begin
        if KEY0_N = '0' then
            auto_run <= '0';
        elsif CLOCK_50'event and CLOCK_50 = '1' then
            if key2_prev = '1' and key2_db = '0' then
                auto_run <= not auto_run;
            end if;
        end if;
    end process;

    -- ===== 时钟分频器 =====
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            if clk_cnt = CLK_DIV-1 then
                clk_cnt <= 0;
                div_ce <= '1';
            else
                clk_cnt <= clk_cnt + 1;
                div_ce <= '0';
            end if;
        end if;
    end process;

    -- FSM 时钟使能：自动模式走分频，手动模式靠单步
    ce <= (auto_run and div_ce) or step_pulse;

    -- ===== CPU 主状态机（同步复位） =====
    process(CLOCK_50, KEY0_N)
    begin
        if KEY0_N = '0' then
            state <= S_FETCH1;
            ac  <= (others => '0');
            pc  <= (others => '0');
            ir  <= (others => '0');
            mar <= (others => '0');
            mdr <= (others => '0');
        elsif CLOCK_50'event and CLOCK_50 = '1' then
            if ce = '1' then
                case state is
                    -- 取指阶段
                    when S_FETCH1 =>
                        mar <= pc;
                        state <= S_FETCH2;
                    when S_FETCH2 =>
                        mdr <= mem(conv_integer(mar));
                        pc <= pc + 1;
                        state <= S_FETCH3;
                    when S_FETCH3 =>
                        ir <= mdr;
                        state <= S_DECODE;

                    -- 译码
                    when S_DECODE =>
                        case ir(15 downto 8) is
                            when x"00" => state <= S_ADD1;
                            when x"01" => state <= S_STORE1;
                            when x"02" => state <= S_LOAD1;
                            when x"03" => state <= S_JUMP;
                            when x"04" => state <= S_JNEG;
                            when others => state <= S_FETCH1;
                        end case;

                    -- ADD: AC <= AC + MEM[address]
                    when S_ADD1 =>
                        mar <= ir(7 downto 0);
                        state <= S_ADD2;
                    when S_ADD2 =>
                        mdr <= mem(conv_integer(mar));
                        state <= S_ADD3;
                    when S_ADD3 =>
                        ac <= ac + mdr;
                        state <= S_FETCH1;

                    -- STORE: MEM[address] <= AC
                    when S_STORE1 =>
                        mar <= ir(7 downto 0);
                        state <= S_STORE2;
                    when S_STORE2 =>
                        mem(conv_integer(mar)) <= ac;
                        state <= S_FETCH1;

                    -- LOAD: AC <= MEM[address]
                    when S_LOAD1 =>
                        mar <= ir(7 downto 0);
                        state <= S_LOAD2;
                    when S_LOAD2 =>
                        mdr <= mem(conv_integer(mar));
                        state <= S_LOAD3;
                    when S_LOAD3 =>
                        ac <= mdr;
                        state <= S_FETCH1;

                    -- JUMP: PC <= address
                    when S_JUMP =>
                        pc <= ir(7 downto 0);
                        state <= S_FETCH1;

                    -- JNEG: if AC<0 then PC <= address
                    when S_JNEG =>
                        if ac(15) = '1' then
                            pc <= ir(7 downto 0);
                        end if;
                        state <= S_FETCH1;
                end case;
            end if;
        end if;
    end process;

    -- ===== 输出映射 =====
    LEDR(7 downto 0) <= ac(7 downto 0);
    LEDR(16) <= SW16;
    LEDR(15 downto 8) <= (others => '0');
    LEDR(17) <= auto_run;
    HEX0 <= to_7seg(ac(3 downto 0));
    HEX1 <= to_7seg(ac(7 downto 4));
    HEX2 <= to_7seg(ac(11 downto 8));
    HEX3 <= to_7seg(ac(15 downto 12));
    HEX4 <= to_7seg(pc(3 downto 0));
    HEX5 <= to_7seg(pc(7 downto 4));
    HEX6 <= to_7seg(ir(11 downto 8));
    HEX7 <= to_7seg(ir(15 downto 12));

    -- FSM 状态编码输出（供 LCD 显示步骤信息）
    FSM_ID <= "0000" when state = S_FETCH1  else
             "0001" when state = S_FETCH2  else
             "0010" when state = S_FETCH3  else
             "0011" when state = S_DECODE  else
             "0100" when state = S_ADD1    else
             "0101" when state = S_ADD2    else
             "0110" when state = S_ADD3    else
             "0111" when state = S_STORE1  else
             "1000" when state = S_STORE2  else
             "1001" when state = S_LOAD1   else
             "1010" when state = S_LOAD2   else
             "1011" when state = S_LOAD3   else
             "1100" when state = S_JUMP    else
             "1101" when state = S_JNEG    else
             "1111";

    PC_O       <= pc;
    AC_O       <= ac;
    IR_O       <= ir;
    STEP_CNT_O <= step_cnt;
    AUTO_RUN_O <= auto_run;
    DETAIL_O   <= SW16;
    FSM_ID_O   <= FSM_ID;

    -- ===== LCD 实例化 =====
    u_lcd : lcd_display
        port map (
            CLOCK_50 => CLOCK_50,
            rst_n    => KEY0_N,
            trigger  => ce,
            detail   => SW16,
            fsm_id   => FSM_ID,
            pc       => pc,
            ac       => ac,
            ir       => ir,
            LCD_DATA => LCD_DATA,
            LCD_RS   => LCD_RS,
            LCD_RW   => LCD_RW,
            LCD_EN   => LCD_EN,
            LCD_ON   => LCD_ON,
            LCD_BLON => LCD_BLON
        );
end behavioral;
