-- 实验4：256x4 ROM存储器（VHDL行为描述）
-- 8位地址线ADR，4位数据输出DOUT，使能端EN
-- 对应教材P124 存储器设计实验
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity rom256x4 is
    port (
        EN   : in  std_logic;
        ADR  : in  std_logic_vector(7 downto 0);
        DOUT : out std_logic_vector(3 downto 0)
    );
end rom256x4;

architecture art of rom256x4 is
    subtype WORD is std_logic_vector(3 downto 0);
    type MEMORY is array(0 to 255) of WORD;

    -- ROM内容信号：初始化为地址的低4位（循环0~15）作为默认值
    function init_rom return MEMORY is
        variable mem : MEMORY;
    begin
        for i in 0 to 255 loop
            mem(i) := conv_std_logic_vector(i mod 16, 4);
        end loop;
        return mem;
    end init_rom;

    signal ROM : MEMORY := init_rom;
    signal ADR_INT : integer range 0 to 255;
begin
    ADR_INT <= conv_integer(ADR);

    process(EN, ADR_INT)
    begin
        if EN = '1' then
            DOUT <= ROM(ADR_INT);
        else
            DOUT <= (others => 'Z');
        end if;
    end process;
end art;
