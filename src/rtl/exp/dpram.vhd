-- 实验4：8x8双口RAM（VHDL行为描述）
-- 支持同时读写，写端口WADD+DATAIN+WE，读端口RADD+RE+DATAOUT
-- 对应教材P123图6.18双口RAM设计
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity dpram is
    generic (
        WIDTH : integer := 8;
        DEPTH : integer := 8;
        ADDR  : integer := 3
    );
    port (
        DATAIN  : in  std_logic_vector(WIDTH-1 downto 0);
        DATAOUT : out std_logic_vector(WIDTH-1 downto 0);
        CLOCK   : in  std_logic;
        WE      : in  std_logic;
        RE      : in  std_logic;                         -- 读使能（教材中R_E）
        WADD    : in  std_logic_vector(ADDR-1 downto 0);
        RADD    : in  std_logic_vector(ADDR-1 downto 0)
    );
end dpram;

architecture art of dpram is
    type MEM is array(DEPTH-1 downto 0) of std_logic_vector(WIDTH-1 downto 0);
    signal RAMTMP : MEM;
begin
    -- 写进程
    process(CLOCK)
    begin
        if CLOCK'event and CLOCK = '1' then
            if WE = '1' then
                RAMTMP(conv_integer(WADD)) <= DATAIN;
            end if;
        end if;
    end process;

    -- 读进程
    process(CLOCK)
    begin
        if CLOCK'event and CLOCK = '1' then
            if RE = '1' then
                DATAOUT <= RAMTMP(conv_integer(RADD));
            end if;
        end if;
    end process;
end art;
