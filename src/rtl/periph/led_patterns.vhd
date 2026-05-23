-- led_patterns.vhd — 彩灯显示引擎 (9种模式)
-- 来源: Exp2 (已验收)
--
-- 模式: 0=全灭, 1=左移单灯, 2=右移单灯, 3=中→外, 4=外→中,
--        5=左→右全亮/全灭, 6=中→外全亮/全灭, 7=外→中全亮/全灭, 8=全闪烁
--
-- 接口: mode_i 直接选择模式, en_i 总开关

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity led_patterns is
    port (
        clk_i        : in  std_logic;      -- 50 MHz
        rst_n_i      : in  std_logic;
        en_i         : in  std_logic;      -- 总开关
        mode_i       : in  std_logic_vector(3 downto 0);  -- 模式 0-8
        mode_next_i  : in  std_logic;      -- 切换到下一模式 (按键脉冲)
        led_o        : out std_logic_vector(10 downto 0)  -- 彩灯输出
    );
end led_patterns;

architecture rtl of led_patterns is

    -- 50MHz → ~2Hz 彩灯时钟
    constant LED_MAX  : integer := 12500000 - 1;
    signal led_cnt    : integer range 0 to LED_MAX := 0;
    signal led_clk    : std_logic := '0';

    -- 按键防抖 (~4kHz)
    constant DB_MAX   : integer := 6103 - 1;
    signal db_cnt     : integer range 0 to DB_MAX := 0;
    signal db_clk     : std_logic := '0';
    signal btn_sync   : std_logic_vector(1 downto 0) := "00";
    signal btn_rise   : std_logic;

    -- 模式与状态
    signal mode       : std_logic_vector(3 downto 0) := "0000";
    signal cled       : std_logic_vector(10 downto 0) := (others => '0');
    signal flag       : std_logic := '0';  -- 方向标志

begin

    -- ============================================================
    -- 时钟分频
    -- ============================================================
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if led_cnt = LED_MAX then
                led_cnt <= 0;
                led_clk <= not led_clk;
            else
                led_cnt <= led_cnt + 1;
            end if;

            if db_cnt = DB_MAX then
                db_cnt <= 0;
                db_clk <= not db_clk;
            else
                db_cnt <= db_cnt + 1;
            end if;
        end if;
    end process;

    -- ============================================================
    -- 模式切换按钮 (消抖后上升沿)
    -- ============================================================
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                btn_sync <= "00";
            else
                btn_sync <= btn_sync(0) & mode_next_i;
            end if;
        end if;
    end process;

    process(db_clk)
        variable btn_prev : std_logic := '0';
    begin
        if rising_edge(db_clk) then
            if btn_sync(1) = '1' and btn_prev = '0' then
                btn_rise <= '1';
            else
                btn_rise <= '0';
            end if;
            btn_prev := btn_sync(1);
        end if;
    end process;

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                mode <= "0000";
            elsif btn_rise = '1' then
                if mode = "1000" then
                    mode <= "0000";
                else
                    mode <= mode + 1;
                end if;
            elsif mode_i /= "0000" then
                mode <= mode_i;  -- 外部设置优先
            end if;
        end if;
    end process;

    -- ============================================================
    -- 彩灯控制 (~2Hz 时钟域)
    -- ============================================================
    process(led_clk, rst_n_i)
    begin
        if rst_n_i = '0' then
            cled <= (others => '0');
            flag <= '0';
        elsif rising_edge(led_clk) then
            if en_i = '0' then
                cled <= (others => '0');
            else
                case mode is
                    when "0000" =>  -- 全灭
                        cled <= (others => '0');

                    when "0001" =>  -- 左移单灯
                        if cled = "00000000000" then
                            cled(10) <= '1';
                        else
                            cled <= '0' & cled(10 downto 1);
                        end if;

                    when "0010" =>  -- 右移单灯
                        if cled = "00000000000" then
                            cled(0) <= '1';
                        else
                            cled <= cled(9 downto 0) & '0';
                        end if;

                    when "0011" =>  -- 中间→两边
                        if cled = "00000000000" then
                            cled(5) <= '1';
                        else
                            cled(10 downto 5) <= cled(9 downto 5) & '0';
                            cled(5 downto 0)  <= '0' & cled(5 downto 1);
                        end if;

                    when "0100" =>  -- 两边→中间
                        if cled = "00000000000" then
                            cled(10) <= '1';
                            cled(0)  <= '1';
                        else
                            cled(10 downto 5) <= '0' & cled(10 downto 6);
                            cled(4 downto 0)  <= cled(3 downto 0) & '0';
                        end if;

                    when "0101" =>  -- 左→右全亮/全灭
                        if flag = '0' then
                            cled <= '1' & cled(10 downto 1);
                        else
                            cled <= cled(9 downto 0) & '0';
                        end if;

                    when "0110" =>  -- 中→外全亮/全灭
                        if flag = '0' then
                            cled(10 downto 5) <= cled(9 downto 5) & '1';
                            cled(5 downto 0)  <= '1' & cled(5 downto 1);
                        else
                            cled(10 downto 5) <= '0' & cled(10 downto 6);
                            cled(5 downto 0)  <= cled(4 downto 0) & '0';
                        end if;

                    when "0111" =>  -- 外→中全亮/全灭
                        if flag = '0' then
                            cled(10 downto 5) <= '1' & cled(10 downto 6);
                            cled(5 downto 0)  <= cled(4 downto 0) & '1';
                        else
                            cled(10 downto 5) <= cled(9 downto 5) & '0';
                            cled(5 downto 0)  <= '0' & cled(5 downto 1);
                        end if;

                    when "1000" =>  -- 全闪烁
                        if flag = '0' then
                            cled <= (others => '1');
                        else
                            cled <= (others => '0');
                        end if;

                    when others =>
                        cled <= (others => '0');
                end case;

                -- 方向标志更新
                if cled = "00000000000" then
                    flag <= '0';
                elsif cled = "11111111111" then
                    flag <= '1';
                end if;
            end if;
        end if;
    end process;

    led_o <= cled;

end rtl;
