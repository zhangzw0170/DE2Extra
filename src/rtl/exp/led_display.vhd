-- 实验2：彩灯显示芯片设计（适配DE2-115）
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity led_display is
    Port (
        clk      : in  std_logic;    -- 系统时钟 50MHz
        sw1      : in  std_logic;    -- 总开关
        an1      : in  std_logic;    -- 模式切换按钮（DE2-115低电平有效）
        segcode2 : out std_logic_vector(6 downto 0);
        segcode1 : out std_logic_vector(6 downto 0);
        segcode0 : out std_logic_vector(6 downto 0);
        cled     : buffer std_logic_vector(10 downto 0)
    );
end led_display;

architecture Behavioral of led_display is
    -- 时钟分频常量
    constant LED_HALF : integer := 12500000;  -- 50MHz/(2Hz*2)
    constant KEY_HALF : integer := 6103;      -- 50MHz/(4096Hz*2)
    signal led_count  : integer range 0 to LED_HALF-1 := 0;
    signal key_count  : integer range 0 to KEY_HALF-1 := 0;
    signal clk1_div   : std_logic := '0';  -- ~2Hz 彩灯时钟
    signal clk2_div   : std_logic := '0';  -- ~4kHz 防抖时钟

    signal an1_active : std_logic;  -- 按键高电平有效
    signal mode       : std_logic_vector(3 downto 0) := "0000";
    signal flag       : std_logic := '0';
    signal ancounter  : std_logic_vector(9 downto 0) := (others => '0');
    signal mode_disp  : std_logic_vector(6 downto 0);
    signal segcode0_i : std_logic_vector(6 downto 0);
    signal segcode1_i : std_logic_vector(6 downto 0);
    signal segcode2_i : std_logic_vector(6 downto 0);
begin

    -- DE2-115按键低电平有效，内部取反为高电平有效
    an1_active <= not an1;

    -- 时钟分频：50MHz -> 2Hz + 4kHz
    process(clk)
    begin
        if clk'event and clk='1' then
            if led_count = LED_HALF-1 then
                led_count <= 0;
                clk1_div <= not clk1_div;
            else
                led_count <= led_count + 1;
            end if;
            if key_count = KEY_HALF-1 then
                key_count <= 0;
                clk2_div <= not clk2_div;
            else
                key_count <= key_count + 1;
            end if;
        end if;
    end process;

    -- 彩灯控制进程
    process(clk1_div, sw1, an1_active, cled)
    begin
        if sw1='1' then
            if clk1_div'event and clk1_div='1' then
                if mode="0000" then
                    cled <= (others=>'0');
                elsif mode="0001" then
                    if cled="00000000000" then
                        cled(10) <= '1';
                    else
                        cled <= '0' & cled(10 downto 1);
                    end if;
                elsif mode="0010" then
                    if cled="00000000000" then
                        cled(0) <= '1';
                    else
                        cled <= cled(9 downto 0) & '0';
                    end if;
                elsif mode="0011" then
                    if cled="00000000000" then
                        cled(5) <= '1';
                    else
                        cled(10 downto 5) <= cled(9 downto 5) & '0';
                        cled(5 downto 0) <= '0' & cled(5 downto 1);
                    end if;
                elsif mode="0100" then
                    if cled="00000000000" then
                        cled(10) <= '1';
                        cled(0) <= '1';
                    else
                        cled(10 downto 5) <= '0' & cled(10 downto 6);
                        cled(4 downto 0) <= cled(3 downto 0) & '0';
                    end if;
                elsif mode="0101" then
                    if flag='0' then
                        cled <= '1' & cled(10 downto 1);
                    else
                        cled <= cled(9 downto 0) & '0';
                    end if;
                elsif mode="0110" then
                    if flag='0' then
                        cled(10 downto 5) <= cled(9 downto 5) & '1';
                        cled(5 downto 0) <= '1' & cled(5 downto 1);
                    else
                        cled(10 downto 5) <= '0' & cled(10 downto 6);
                        cled(5 downto 0) <= cled(4 downto 0) & '0';
                    end if;
                elsif mode="0111" then
                    if flag='0' then
                        cled(10 downto 5) <= '1' & cled(10 downto 6);
                        cled(5 downto 0) <= cled(4 downto 0) & '1';
                    else
                        cled(10 downto 5) <= cled(9 downto 5) & '0';
                        cled(5 downto 0) <= '0' & cled(5 downto 1);
                    end if;
                elsif mode="1000" then
                    if flag='0' then
                        cled <= (others=>'1');
                    else
                        cled <= (others=>'0');
                    end if;
                else
                    cled <= (others=>'0');
                end if;

                if cled="00000000000" then
                    flag <= '0';
                elsif cled="11111111111" then
                    flag <= '1';
                else
                    null;
                end if;
            end if;
        else
            cled <= (others=>'0');
        end if;
    end process;

    -- 显示控制进程
    process(sw1, mode, mode_disp)
    begin
        if sw1='1' then
            if mode="0000" then
                segcode0_i <= "1010000";
                segcode1_i <= "0111000";
                segcode2_i <= "0111001";
            else
                segcode0_i <= mode_disp;
                segcode1_i <= "1110001";
                segcode2_i <= "0111000";
            end if;
            case mode is
                when "0001" => mode_disp <= "0000110";
                when "0010" => mode_disp <= "1011011";
                when "0011" => mode_disp <= "1001111";
                when "0100" => mode_disp <= "1100110";
                when "0101" => mode_disp <= "1101101";
                when "0110" => mode_disp <= "1111101";
                when "0111" => mode_disp <= "0000111";
                when "1000" => mode_disp <= "1111111";
                when others => mode_disp <= "0000000";
            end case;
        else
            segcode0_i <= "1110001";
            segcode1_i <= "1110001";
            segcode2_i <= "0111111";
        end if;
    end process;

    -- 数码管输出取反（DE2-115共阳极适配）
    segcode0 <= not segcode0_i;
    segcode1 <= not segcode1_i;
    segcode2 <= not segcode2_i;

    -- 键盘防抖（使用4kHz分频时钟）
    process(clk2_div, an1_active)
    begin
        if an1_active='1' then
            if clk2_div'event and clk2_div='1' then
                if ancounter(9)='0' then
                    ancounter <= ancounter+1;
                end if;
            end if;
        else
            ancounter <= (others=>'0');
        end if;
    end process;

    -- 模式切换
    process(ancounter(9), sw1)
    begin
        if sw1='1' then
            if ancounter(9)'event and ancounter(9)='1' then
                if mode="1000" then
                    mode <= "0000";
                else
                    mode <= mode+1;
                end if;
            end if;
        else
            mode <= "0000";
        end if;
    end process;

end Behavioral;
