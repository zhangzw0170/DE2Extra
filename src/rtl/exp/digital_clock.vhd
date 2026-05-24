-- ============================================================================
-- 实验3 模式11：数字电子钟 (11-mode clock per 电子钟技术规格书)
-- ============================================================================
-- 子模式选择: SW15-SW14 → LEDR15-LEDR14 显示当前子模式
--   00 = 时间显示  01 = 时间设置  10 = 闹钟显示  11 = 闹钟设置
-- 显示格式: HEX7-6 (HH), HEX5-4 (MM), HEX3-2 (SS), HEX1 (空), HEX0 ('A'/空)
-- 设置方式: SW7-4 (十位BCD) + SW3-0 (个位BCD) → KEY2(时)/KEY1(分)/KEY0(秒)
--   写入前检查BCD合法性，不合法时LEDG7-0闪一次(~0.5s)
-- 闹钟: SW13 使能，生效时 HEX0='A', LEDG7-0 跟随秒闪烁，至该分钟结束
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity digital_clock is
    port (
        clk          : in  std_logic;                      -- 50MHz
        reset_n      : in  std_logic;                      -- KEY3 复位（低有效）
        sw_mode      : in  std_logic_vector(1 downto 0);   -- SW15-SW14 子模式
        sw_alarm_en  : in  std_logic;                      -- SW13 闹钟使能
        sw_bcd_hi    : in  std_logic_vector(3 downto 0);   -- SW7-SW4  十位BCD
        sw_bcd_lo    : in  std_logic_vector(3 downto 0);   -- SW3-SW0  个位BCD
        key_n        : in  std_logic_vector(2 downto 0);   -- KEY_N[2:0] 低有效
        hex7, hex6, hex5, hex4 : out std_logic_vector(6 downto 0);
        hex3, hex2, hex1, hex0 : out std_logic_vector(6 downto 0);
        ledr_mode    : out std_logic_vector(1 downto 0);   -- LEDR15-14
        ledr_alarm   : out std_logic;                      -- LEDR13
        ledr_bcd_hi  : out std_logic_vector(3 downto 0);   -- LEDR7-4
        ledr_bcd_lo  : out std_logic_vector(3 downto 0);   -- LEDR3-0
        ledg         : out std_logic_vector(7 downto 0)    -- LEDG7-0
    );
end digital_clock;

architecture behavioral of digital_clock is
    -- =====================================================================
    -- 1Hz tick
    -- =====================================================================
    constant CNT_1HZ_MAX : integer := 50000000 - 1;  -- 50MHz → 1s
    signal cnt_1hz       : integer range 0 to CNT_1HZ_MAX := 0;
    signal tick_1hz      : std_logic := '0';

    -- =====================================================================
    -- 按键去抖 (20ms @ 50MHz = 1,000,000 cycles)
    -- =====================================================================
    constant DB_MAX       : integer := 1000000 - 1;
    type db_cnt_arr is array(2 downto 0) of integer range 0 to DB_MAX;
    signal db_cnt         : db_cnt_arr := (others => 0);
    signal key_db         : std_logic_vector(2 downto 0) := "111";
    signal key_prev       : std_logic_vector(2 downto 0) := "111";
    signal key_press      : std_logic_vector(2 downto 0);  -- 1-cycle pulse

    -- =====================================================================
    -- 时间寄存器 (BCD)
    -- =====================================================================
    signal sec_lo, sec_hi : std_logic_vector(3 downto 0) := "0000";
    signal min_lo, min_hi : std_logic_vector(3 downto 0) := "0000";
    signal hor_lo, hor_hi : std_logic_vector(3 downto 0) := "0000";

    -- =====================================================================
    -- 闹钟寄存器 (BCD, 仅 HH:MM)
    -- =====================================================================
    signal alm_min_lo, alm_min_hi : std_logic_vector(3 downto 0) := "0000";
    signal alm_hor_lo, alm_hor_hi : std_logic_vector(3 downto 0) := "0000";

    -- =====================================================================
    -- BCD 合法性检查
    -- =====================================================================
    function bcd_legal_hour(hi, lo : std_logic_vector(3 downto 0)) return boolean is
        variable val : integer;
    begin
        val := to_integer(unsigned(hi)) * 10 + to_integer(unsigned(lo));
        return (val >= 0 and val <= 23);
    end function;

    function bcd_legal_minsec(hi, lo : std_logic_vector(3 downto 0)) return boolean is
        variable val : integer;
    begin
        if unsigned(hi) > 5 then return false; end if;
        if unsigned(lo) > 9 then return false; end if;
        val := to_integer(unsigned(hi)) * 10 + to_integer(unsigned(lo));
        return (val >= 0 and val <= 59);
    end function;

    -- =====================================================================
    -- 非法写入闪烁控制 (2Hz blink, 1s duration)
    -- =====================================================================
    constant FLASH_MAX : integer := 50000000 - 1;   -- 1s 总时长
    constant BLINK_HALF: integer := 12500000 - 1;   -- 0.25s 半周期 → 2Hz
    signal flash_cnt   : integer range 0 to FLASH_MAX := 0;
    signal blink_cnt   : integer range 0 to BLINK_HALF := 0;
    signal flash_active: std_logic := '0';
    signal flash_blink : std_logic := '0';
    signal illegal_trig: std_logic := '0';  -- 1-cycle trigger

    -- =====================================================================
    -- KEY3 复位脉冲
    -- =====================================================================
    signal reset_pulse : std_logic := '0';

    -- =====================================================================
    -- 2Hz 全局闪烁 (闹钟用)
    -- =====================================================================
    constant BLINK2HZ_MAX : integer := 12500000 - 1;  -- 0.25s @ 50MHz
    signal blink2hz_cnt   : integer range 0 to BLINK2HZ_MAX := 0;
    signal blink2hz       : std_logic := '0';

    -- =====================================================================
    -- 闹钟触发
    -- =====================================================================
    signal alarm_match    : std_logic := '0';
    signal alarm_active   : std_logic;  -- SW13=1 AND alarm_match

    -- =====================================================================
    -- 7段译码
    -- =====================================================================
    function to_7seg(val : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable s : std_logic_vector(6 downto 0);
    begin
        case val is
            when "0000" => s := "1000000";  -- 0
            when "0001" => s := "1111001";  -- 1
            when "0010" => s := "0100100";  -- 2
            when "0011" => s := "0110000";  -- 3
            when "0100" => s := "0011001";  -- 4
            when "0101" => s := "0010010";  -- 5
            when "0110" => s := "0000010";  -- 6
            when "0111" => s := "1111000";  -- 7
            when "1000" => s := "0000000";  -- 8
            when "1001" => s := "0010000";  -- 9
            when others => s := "1111111";  -- blank
        end case;
        return s;
    end function;

    constant SEG_A     : std_logic_vector(6 downto 0) := "0001000";  -- 'A'
    constant SEG_S     : std_logic_vector(6 downto 0) := "0010010";  -- 'S' (同5)
    constant SEG_BLANK : std_logic_vector(6 downto 0) := "1111111";  -- 全灭
    constant SEG_DASH  : std_logic_vector(6 downto 0) := "0111111";  -- '-'

begin
    -- =====================================================================
    -- KEY3 复位：同步 + 下降沿检测 → 1-cycle reset_pulse
    -- =====================================================================
    process(clk)
        variable rst_sync : std_logic_vector(1 downto 0) := "11";
        variable rst_prev : std_logic := '1';
    begin
        if rising_edge(clk) then
            rst_sync(0) := reset_n;
            rst_sync(1) := rst_sync(0);
            reset_pulse <= '0';
            if rst_prev = '1' and rst_sync(1) = '0' then
                reset_pulse <= '1';
            end if;
            rst_prev := rst_sync(1);
        end if;
    end process;

    -- =====================================================================
    -- 1Hz tick 产生
    -- =====================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if reset_pulse = '1' then
                cnt_1hz  <= 0;
                tick_1hz <= '0';
            elsif cnt_1hz = CNT_1HZ_MAX then
                cnt_1hz  <= 0;
                tick_1hz <= '1';
            else
                cnt_1hz  <= cnt_1hz + 1;
                tick_1hz <= '0';
            end if;
        end if;
    end process;

    -- =====================================================================
    -- 2Hz blink 产生
    -- =====================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if blink2hz_cnt = BLINK2HZ_MAX then
                blink2hz <= not blink2hz;
                blink2hz_cnt <= 0;
            else
                blink2hz_cnt <= blink2hz_cnt + 1;
            end if;
        end if;
    end process;

    -- =====================================================================
    -- 按键去抖 (3个key并行)
    -- =====================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            for i in 0 to 2 loop
                if key_n(i) /= key_db(i) then
                    if db_cnt(i) = DB_MAX then
                        key_db(i) <= key_n(i);
                        db_cnt(i) <= 0;
                    else
                        db_cnt(i) <= db_cnt(i) + 1;
                    end if;
                else
                    db_cnt(i) <= 0;
                end if;
            end loop;
        end if;
    end process;

    -- =====================================================================
    -- 按键下降沿检测 (1→0: 按下)
    -- =====================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            key_prev <= key_db;
        end if;
    end process;

    gen_press: for i in 0 to 2 generate
        key_press(i) <= '1' when key_prev(i) = '1' and key_db(i) = '0' else '0';
    end generate;

    -- =====================================================================
    -- 时间计数 + 写入逻辑 (合并到同一进程解决多驱动问题)
    -- =====================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            illegal_trig <= '0';  -- default

            -- ----- KEY3 复位 -----
            if reset_pulse = '1' then
                sec_lo    <= "0000"; sec_hi    <= "0000";
                min_lo    <= "0000"; min_hi    <= "0000";
                hor_lo    <= "0000"; hor_hi    <= "0000";
                alm_min_lo<= "0000"; alm_min_hi<= "0000";
                alm_hor_lo<= "0000"; alm_hor_hi<= "0000";

            else

            -- ----- 1Hz 走时 -----
            if tick_1hz = '1' then
                -- 秒进位
                if sec_lo = "1001" then
                    sec_lo <= "0000";
                    if sec_hi = "0101" then
                        sec_hi <= "0000";
                        -- 分进位
                        if min_lo = "1001" then
                            min_lo <= "0000";
                            if min_hi = "0101" then
                                min_hi <= "0000";
                                -- 时进位
                                if hor_lo = "1001" then
                                    hor_lo <= "0000";
                                    if hor_hi = "0010" then
                                        hor_hi <= "0000";
                                    else
                                        hor_hi <= hor_hi + 1;
                                    end if;
                                elsif hor_hi = "0010" and hor_lo = "0011" then
                                    -- 23:59:59 → 00:00:00
                                    hor_hi <= "0000";
                                    hor_lo <= "0000";
                                else
                                    hor_lo <= hor_lo + 1;
                                end if;
                            else
                                min_hi <= min_hi + 1;
                            end if;
                        else
                            min_lo <= min_lo + 1;
                        end if;
                    else
                        sec_hi <= sec_hi + 1;
                    end if;
                else
                    sec_lo <= sec_lo + 1;
                end if;
            end if;

            -- ----- 按键写入 (模式01=时间设置, 模式11=闹钟设置) -----
            if sw_mode = "01" then
                if key_press(2) = '1' then  -- KEY2: 写时
                    if bcd_legal_hour(sw_bcd_hi, sw_bcd_lo) then
                        hor_hi <= sw_bcd_hi;
                        hor_lo <= sw_bcd_lo;
                    else
                        illegal_trig <= '1';
                    end if;
                end if;
                if key_press(1) = '1' then  -- KEY1: 写分
                    if bcd_legal_minsec(sw_bcd_hi, sw_bcd_lo) then
                        min_hi <= sw_bcd_hi;
                        min_lo <= sw_bcd_lo;
                    else
                        illegal_trig <= '1';
                    end if;
                end if;
                if key_press(0) = '1' then  -- KEY0: 写秒
                    if bcd_legal_minsec(sw_bcd_hi, sw_bcd_lo) then
                        sec_hi <= sw_bcd_hi;
                        sec_lo <= sw_bcd_lo;
                    else
                        illegal_trig <= '1';
                    end if;
                end if;

            elsif sw_mode = "11" then
                if key_press(2) = '1' then  -- KEY2: 写闹钟时
                    if bcd_legal_hour(sw_bcd_hi, sw_bcd_lo) then
                        alm_hor_hi <= sw_bcd_hi;
                        alm_hor_lo <= sw_bcd_lo;
                    else
                        illegal_trig <= '1';
                    end if;
                end if;
                if key_press(1) = '1' then  -- KEY1: 写闹钟分
                    if bcd_legal_minsec(sw_bcd_hi, sw_bcd_lo) then
                        alm_min_hi <= sw_bcd_hi;
                        alm_min_lo <= sw_bcd_lo;
                    else
                        illegal_trig <= '1';
                    end if;
                end if;
                -- KEY0: 闹钟无秒，忽略
            end if;
            end if;  -- reset_pulse / else
        end if;
    end process;

    -- =====================================================================
    -- 非法闪烁定时器 (0.5s one-shot)
    -- =====================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if illegal_trig = '1' then
                flash_cnt    <= 0;
                blink_cnt    <= 0;
                flash_active <= '1';
                flash_blink  <= '1';
            elsif flash_active = '1' then
                if flash_cnt = FLASH_MAX then
                    flash_active <= '0';
                    flash_cnt    <= 0;
                else
                    flash_cnt <= flash_cnt + 1;
                end if;
                if blink_cnt = BLINK_HALF then
                    flash_blink <= not flash_blink;
                    blink_cnt   <= 0;
                else
                    blink_cnt <= blink_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- =====================================================================
    -- 闹钟匹配与使能
    -- =====================================================================
    alarm_match <= '1' when (hor_hi = alm_hor_hi and hor_lo = alm_hor_lo
                        and min_hi = alm_min_hi and min_lo = alm_min_lo) else '0';
    alarm_active <= sw_alarm_en and alarm_match;

    -- =====================================================================
    -- 数码管输出 (按子模式选择)
    -- =====================================================================
    process(sw_mode, hor_hi, hor_lo, min_hi, min_lo, sec_hi, sec_lo,
            alm_hor_hi, alm_hor_lo, alm_min_hi, alm_min_lo, sw_alarm_en)
    begin
        case sw_mode is
            when "00" =>  -- 时间显示
                hex7 <= to_7seg(hor_hi);
                hex6 <= to_7seg(hor_lo);
                hex5 <= to_7seg(min_hi);
                hex4 <= to_7seg(min_lo);
                hex3 <= to_7seg(sec_hi);
                hex2 <= to_7seg(sec_lo);
            when "01" =>  -- 时间设置 (闪烁当前秒?)
                hex7 <= to_7seg(hor_hi);
                hex6 <= to_7seg(hor_lo);
                hex5 <= to_7seg(min_hi);
                hex4 <= to_7seg(min_lo);
                hex3 <= to_7seg(sec_hi);
                hex2 <= to_7seg(sec_lo);
            when "10" =>  -- 闹钟显示 (HH-MM + --)
                hex7 <= to_7seg(alm_hor_hi);
                hex6 <= to_7seg(alm_hor_lo);
                hex5 <= to_7seg(alm_min_hi);
                hex4 <= to_7seg(alm_min_lo);
                hex3 <= SEG_DASH;
                hex2 <= SEG_DASH;
            when others =>  -- 闹钟设置 (HH-MM + "--")
                hex7 <= to_7seg(alm_hor_hi);
                hex6 <= to_7seg(alm_hor_lo);
                hex5 <= to_7seg(alm_min_hi);
                hex4 <= to_7seg(alm_min_lo);
                hex3 <= SEG_DASH;
                hex2 <= SEG_DASH;
        end case;

        -- HEX1: 始终空白
        hex1 <= SEG_BLANK;

        -- HEX0: 设置模式显示 'S'（优先），否则闹钟使能显示 'A'
        if sw_mode = "01" or sw_mode = "11" then
            hex0 <= SEG_S;
        elsif sw_alarm_en = '1' then
            hex0 <= SEG_A;
        else
            hex0 <= SEG_BLANK;
        end if;
    end process;

    -- =====================================================================
    -- LEDR 输出 (低有效: '0'=亮, '1'=灭) — echo SW state
    -- =====================================================================
    ledr_mode   <= sw_mode;           -- LEDR15-14: 子模式状态 (1=亮)
    ledr_alarm  <= sw_alarm_en;       -- LEDR13: 闹钟使能 (1=亮)
    ledr_bcd_hi <= sw_bcd_hi;         -- LEDR7-4:  十位BCD
    ledr_bcd_lo <= sw_bcd_lo;         -- LEDR3-0:  个位BCD

    -- =====================================================================
    -- LEDG 输出 (低有效: '0'=亮, '1'=灭)
    --   非法: 0.5s 全亮 → 灭
    --   闹钟: 跟随秒闪烁
    -- =====================================================================
    process(flash_active, flash_blink, alarm_active, blink2hz)
    begin
        if flash_active = '1' and flash_blink = '1' then
            ledg <= (others => '1');  -- 非法闪烁: 2Hz blink
        elsif alarm_active = '1' and blink2hz = '1' then
            ledg <= (others => '1');  -- 闹钟: 2Hz blink
        else
            ledg <= (others => '0');  -- 全灭
        end if;
    end process;

end behavioral;
