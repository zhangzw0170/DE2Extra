-- 实验4：存储器芯片设计（顶层模块）
-- 32x8双口RAM
-- 当前 expdemo 版本使用本地 dpram（实验内 BRAM），并不直接占用系统
-- SDRAM 地址空间。若后续在 de2os/RTOS 场景把 Exp4 改造成 SDRAM-backed
-- 演示，必须为它单独预留/隔离存储区，避免与系统堆、任务栈或帧缓冲重叠。
-- SW15-11=地址(读写共用), SW7-0=数据, SW17=模式(1写0读)
-- 写模式: KEY0按下触发写入, LEDR16亮1秒确认
-- 读模式: 实时显示地址对应数据到HEX1-0和LEDG7-0, 无需KEY0
-- LEDRx(除16外)始终指示SWx状态, LEDR16=写确认指示
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity ram_top is
    port (
        CLOCK_50 : in  std_logic;
        KEY0_N   : in  std_logic;
        SW       : in  std_logic_vector(17 downto 0);
        LEDR     : out std_logic_vector(17 downto 0);
        LEDG     : out std_logic_vector(8 downto 0);
        HEX0     : out std_logic_vector(6 downto 0);
        HEX1     : out std_logic_vector(6 downto 0);
        HEX2     : out std_logic_vector(6 downto 0);
        HEX3     : out std_logic_vector(6 downto 0);
        HEX4     : out std_logic_vector(6 downto 0);
        HEX5     : out std_logic_vector(6 downto 0);
        HEX6     : out std_logic_vector(6 downto 0)
    );
end ram_top;

architecture behavioral of ram_top is
    signal data_out      : std_logic_vector(7 downto 0);
    signal we_reg        : std_logic;
    signal re_reg        : std_logic;
    signal key0_prev     : std_logic := '1';
    signal key_pulse     : std_logic;
    signal write_ack     : std_logic := '0';
    signal write_ack_cnt : integer range 0 to 50000000 := 0;

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

    constant BLANK : std_logic_vector(6 downto 0) := "1111111";
begin
    -- KEY0按下检测（下降沿）
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            key0_prev <= KEY0_N;
        end if;
    end process;
    key_pulse <= '1' when key0_prev = '1' and KEY0_N = '0' else '0';

    -- WE: 仅写模式KEY0按下时一个脉冲
    -- RE: 读模式下常开（实时读取，无需KEY0）
    we_reg <= key_pulse and SW(17);
    re_reg <= not SW(17);

    -- RAM例化
    u_ram : entity work.dpram
        generic map (WIDTH => 8, DEPTH => 32, ADDR => 5)
        port map (
            DATAIN  => SW(7 downto 0),
            DATAOUT => data_out,
            CLOCK   => CLOCK_50,
            WE      => we_reg,
            RE      => re_reg,
            WADD    => SW(15 downto 11),
            RADD    => SW(15 downto 11)
        );

    -- 写确认: LEDR16亮1秒后熄灭
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            if key_pulse = '1' and SW(17) = '1' then
                write_ack <= '1';
                write_ack_cnt <= 0;
            elsif write_ack = '1' then
                if write_ack_cnt = 50000000 then
                    write_ack <= '0';
                else
                    write_ack_cnt <= write_ack_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- LEDR: 镜像SW
    LEDR <= SW;

    -- LEDG[8]=写确认, LEDG[7:0]=读模式下实时显示读出数据
    LEDG <= write_ack & data_out when SW(17) = '0' else write_ack & "00000000";

    -- 7段数码管
    HEX6 <= BLANK;
    HEX5 <= to_7seg("000" & SW(15));
    HEX4 <= to_7seg(SW(14 downto 11));
    HEX2 <= BLANK;
    HEX3 <= BLANK;

    process(SW, data_out)
    begin
        if SW(17) = '1' then
            -- 写模式: HEX1-0显示待写入数据
            HEX1 <= to_7seg(SW(7 downto 4));
            HEX0 <= to_7seg(SW(3 downto 0));
        else
            -- 读模式: HEX1-0实时显示读出数据
            HEX1 <= to_7seg(data_out(7 downto 4));
            HEX0 <= to_7seg(data_out(3 downto 0));
        end if;
    end process;

end behavioral;
