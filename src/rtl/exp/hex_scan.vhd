-- 实验3 任务2：8位7段数码管循环显示控制
-- 8个数码管（HEX7~HEX0）循环显示0,1,2,...,E,F共16个字符
-- 每个数码管独立滚动，扫描时钟 freq_scan 控制切换速度
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity hex_scan is
    port (
        clk      : in  std_logic;                      -- 系统时钟（50MHz）
        reset    : in  std_logic;                      -- 复位（低有效）
        seg_out0 : out std_logic_vector(6 downto 0);   -- HEX0 段码 gfedcba
        seg_out1 : out std_logic_vector(6 downto 0);   -- HEX1
        seg_out2 : out std_logic_vector(6 downto 0);   -- HEX2
        seg_out3 : out std_logic_vector(6 downto 0);   -- HEX3
        seg_out4 : out std_logic_vector(6 downto 0);   -- HEX4
        seg_out5 : out std_logic_vector(6 downto 0);   -- HEX5
        seg_out6 : out std_logic_vector(6 downto 0);   -- HEX6
        seg_out7 : out std_logic_vector(6 downto 0)    -- HEX7
    );
end hex_scan;

architecture behavioral of hex_scan is
    -- 分频计数器：将50MHz降到约1Hz（肉眼可见）
    signal clk_div    : std_logic_vector(25 downto 0) := (others => '0');
    signal clk_1hz    : std_logic := '0';

    -- 8个独立的4位计数器（每个数码管一个值）
    type hex_arr is array(0 to 7) of std_logic_vector(3 downto 0);
    signal hex_val : hex_arr := (others => "0000");

    -- 7段译码函数（共阳极，gfedcba，0点亮/1熄灭）
    function to_7seg(val : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable seg : std_logic_vector(6 downto 0);
    begin
        case val is
            when "0000" => seg := "1000000";  -- 0
            when "0001" => seg := "1111001";  -- 1
            when "0010" => seg := "0100100";  -- 2
            when "0011" => seg := "0110000";  -- 3
            when "0100" => seg := "0011001";  -- 4
            when "0101" => seg := "0010010";  -- 5
            when "0110" => seg := "0000010";  -- 6
            when "0111" => seg := "1111000";  -- 7
            when "1000" => seg := "0000000";  -- 8
            when "1001" => seg := "0010000";  -- 9
            when "1010" => seg := "0001000";  -- A
            when "1011" => seg := "0000011";  -- B
            when "1100" => seg := "1000110";  -- C
            when "1101" => seg := "0100001";  -- D
            when "1110" => seg := "0000110";  -- E
            when "1111" => seg := "0001110";  -- F
            when others => seg := "1111111";  -- 全灭
        end case;
        return seg;
    end to_7seg;
begin
    -- 时钟分频：产生约1Hz的扫描时钟
    process(clk, reset)
    begin
        if reset = '0' then
            clk_div <= (others => '0');
            clk_1hz <= '0';
        elsif clk'event and clk = '1' then
            if clk_div = "01011111010111100001000000" then  -- 25,000,000
                clk_div <= (others => '0');
                clk_1hz <= not clk_1hz;
            else
                clk_div <= clk_div + 1;
            end if;
        end if;
    end process;

    -- 每秒钟所有数码管数值+1（0-F循环）
    process(clk_1hz, reset)
    begin
        if reset = '0' then
            hex_val <= (others => "0000");
        elsif clk_1hz'event and clk_1hz = '1' then
            for i in 0 to 7 loop
                if hex_val(i) = "1111" then
                    hex_val(i) <= "0000";
                else
                    hex_val(i) <= hex_val(i) + 1;
                end if;
            end loop;
        end if;
    end process;

    -- 段码输出
    seg_out0 <= to_7seg(hex_val(0));
    seg_out1 <= to_7seg(hex_val(1));
    seg_out2 <= to_7seg(hex_val(2));
    seg_out3 <= to_7seg(hex_val(3));
    seg_out4 <= to_7seg(hex_val(4));
    seg_out5 <= to_7seg(hex_val(5));
    seg_out6 <= to_7seg(hex_val(6));
    seg_out7 <= to_7seg(hex_val(7));
end behavioral;
