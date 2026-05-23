-- digital_clock_core.vhd — 24h 数字电子钟核心
-- 来源: Exp3 (已验收)
--
-- 50MHz → 1Hz tick → BCD 时/分/秒计数器
-- 闹钟: HH:MM 匹配 + 使能 → alarm_o = '1'
-- 输出: BCD 时间寄存器, 闹钟匹配信号

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity digital_clock_core is
    port (
        clk_i          : in  std_logic;
        rst_n_i        : in  std_logic;

        -- 时间设置 (BCD)
        set_hour_hi_i  : in  std_logic_vector(3 downto 0);
        set_hour_lo_i  : in  std_logic_vector(3 downto 0);
        set_min_hi_i   : in  std_logic_vector(3 downto 0);
        set_min_lo_i   : in  std_logic_vector(3 downto 0);
        set_sec_hi_i   : in  std_logic_vector(3 downto 0);
        set_sec_lo_i   : in  std_logic_vector(3 downto 0);
        set_hour_en_i  : in  std_logic;   -- 写入时
        set_min_en_i   : in  std_logic;   -- 写入分
        set_sec_en_i   : in  std_logic;   -- 写入秒

        -- 闹钟设置
        alm_hour_hi_i  : in  std_logic_vector(3 downto 0);
        alm_hour_lo_i  : in  std_logic_vector(3 downto 0);
        alm_min_hi_i   : in  std_logic_vector(3 downto 0);
        alm_min_lo_i   : in  std_logic_vector(3 downto 0);
        alm_en_i       : in  std_logic;   -- 闹钟使能

        -- 输出 (BCD)
        hour_hi_o      : out std_logic_vector(3 downto 0);
        hour_lo_o      : out std_logic_vector(3 downto 0);
        min_hi_o       : out std_logic_vector(3 downto 0);
        min_lo_o       : out std_logic_vector(3 downto 0);
        sec_hi_o       : out std_logic_vector(3 downto 0);
        sec_lo_o       : out std_logic_vector(3 downto 0);

        tick_1hz_o     : out std_logic;   -- 秒脉冲
        alarm_o        : out std_logic    -- 闹钟触发
    );
end digital_clock_core;

architecture rtl of digital_clock_core is

    -- 1Hz tick
    constant CNT_1HZ_MAX : integer := 50000000 - 1;
    signal cnt_1hz       : integer range 0 to CNT_1HZ_MAX := 0;
    signal tick_1hz      : std_logic := '0';

    -- BCD 计数器
    signal sec_lo, sec_hi : std_logic_vector(3 downto 0) := "0000";
    signal min_lo, min_hi : std_logic_vector(3 downto 0) := "0000";
    signal hor_lo, hor_hi : std_logic_vector(3 downto 0) := "0000";

    -- BCD 合法性
    function bcd_valid(hi, lo : std_logic_vector(3 downto 0)) return boolean is
    begin
        if hi > "1001" or lo > "1001" then
            return false;
        end if;
        return true;
    end function;

    function hour_valid(hi, lo : std_logic_vector(3 downto 0)) return boolean is
        variable val : integer;
    begin
        if not bcd_valid(hi, lo) then
            return false;
        end if;
        val := to_integer(unsigned(hi)) * 10 + to_integer(unsigned(lo));
        return (val >= 0 and val <= 23);
    end function;

    function minsec_valid(hi, lo : std_logic_vector(3 downto 0)) return boolean is
        variable val : integer;
    begin
        if not bcd_valid(hi, lo) then
            return false;
        end if;
        val := to_integer(unsigned(hi)) * 10 + to_integer(unsigned(lo));
        return (val >= 0 and val <= 59);
    end function;

begin

    -- ============================================================
    -- 1Hz tick 生成
    -- ============================================================
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
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

    tick_1hz_o <= tick_1hz;

    -- ============================================================
    -- BCD 时间计数器
    -- ============================================================
    process(clk_i)
        variable carry : std_logic;
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                sec_lo <= "0000"; sec_hi <= "0000";
                min_lo <= "0000"; min_hi <= "0000";
                hor_lo <= "0000"; hor_hi <= "0000";

            elsif set_sec_en_i = '1' and minsec_valid(set_sec_hi_i, set_sec_lo_i) then
                sec_lo <= set_sec_lo_i;
                sec_hi <= set_sec_hi_i;

            elsif set_min_en_i = '1' and minsec_valid(set_min_hi_i, set_min_lo_i) then
                min_lo <= set_min_lo_i;
                min_hi <= set_min_hi_i;

            elsif set_hour_en_i = '1' and hour_valid(set_hour_hi_i, set_hour_lo_i) then
                hor_lo <= set_hour_lo_i;
                hor_hi <= set_hour_hi_i;

            elsif tick_1hz = '1' then
                -- 秒进位
                if sec_lo = "1001" then
                    sec_lo <= "0000";
                    carry := '1';
                else
                    sec_lo <= sec_lo + 1;
                    carry := '0';
                end if;

                if carry = '1' then
                    if sec_hi = "0101" then
                        sec_hi <= "0000";
                        carry := '1';
                    else
                        sec_hi <= sec_hi + 1;
                        carry := '0';
                    end if;

                    -- 分进位
                    if carry = '1' then
                        if min_lo = "1001" then
                            min_lo <= "0000";
                            carry := '1';
                        else
                            min_lo <= min_lo + 1;
                            carry := '0';
                        end if;

                        if carry = '1' then
                            if min_hi = "0101" then
                                min_hi <= "0000";
                                carry := '1';
                            else
                                min_hi <= min_hi + 1;
                                carry := '0';
                            end if;

                            -- 时进位 (24h)
                            if carry = '1' then
                                if hor_hi = "0010" and hor_lo = "0011" then
                                    hor_hi <= "0000";
                                    hor_lo <= "0000";
                                elsif hor_lo = "1001" then
                                    hor_lo <= "0000";
                                    hor_hi <= hor_hi + 1;
                                else
                                    hor_lo <= hor_lo + 1;
                                end if;
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ============================================================
    -- 闹钟匹配
    -- ============================================================
    alarm_o <= '1' when alm_en_i = '1'
        and hor_hi = alm_hour_hi_i and hor_lo = alm_hour_lo_i
        and min_hi = alm_min_hi_i and min_lo = alm_min_lo_i
        else '0';

    -- ============================================================
    -- 输出
    -- ============================================================
    hour_hi_o <= hor_hi;  hour_lo_o <= hor_lo;
    min_hi_o  <= min_hi;  min_lo_o  <= min_lo;
    sec_hi_o  <= sec_hi;  sec_lo_o  <= sec_lo;

end rtl;
