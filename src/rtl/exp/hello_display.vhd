-- 实验3 模式01：固定显示HELO
-- A0A1A2=000~010时，HEX3=H HEX2=E HEX1=L HEX0=O
-- 其他值时全灭
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity hello_display is
    port (
        A0, A1, A2 : in  std_logic;
        hex3       : out std_logic_vector(6 downto 0);
        hex2       : out std_logic_vector(6 downto 0);
        hex1       : out std_logic_vector(6 downto 0);
        hex0       : out std_logic_vector(6 downto 0)
    );
end hello_display;

architecture behavioral of hello_display is
    signal input_val : std_logic_vector(2 downto 0);
    constant BLANK   : std_logic_vector(6 downto 0) := "1111111";
    constant SEG_H   : std_logic_vector(6 downto 0) := "0001001";
    constant SEG_E   : std_logic_vector(6 downto 0) := "0000110";
    constant SEG_L   : std_logic_vector(6 downto 0) := "1000111";
    constant SEG_O   : std_logic_vector(6 downto 0) := "1000000";
begin
    input_val <= A2 & A1 & A0;

    process(input_val)
    begin
        if input_val = "000" or input_val = "001" or input_val = "010" then
            hex3 <= SEG_H;
            hex2 <= SEG_E;
            hex1 <= SEG_L;
            hex0 <= SEG_O;
        else
            hex3 <= BLANK;
            hex2 <= BLANK;
            hex1 <= BLANK;
            hex0 <= BLANK;
        end if;
    end process;
end behavioral;
