-- 实验3 顶层模块：4模式切换 (SW17-SW16)
--   00: seg_decoder   01: hello_display   10: hex_scan   11: digital_clock
-- 模式11 (digital_clock) 内部子模式由 SW15-SW14 控制
-- LEDR: 模式11时显示子模式与BCD值，否则全灭
-- LEDG: 模式11时由 digital_clock 控制 (flash), 否则全灭

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity exp3_top is
    port (
        CLOCK_50 : in  std_logic;
        SW       : in  std_logic_vector(17 downto 0);
        KEY_N    : in  std_logic_vector(3 downto 0);
        HEX      : out std_logic_vector(55 downto 0);    -- HEX7~HEX0
        LEDR     : out std_logic_vector(17 downto 0);    -- 红色LED
        LEDG     : out std_logic_vector(8 downto 0)      -- 绿色LED
    );
end exp3_top;

architecture behavioral of exp3_top is
    signal mode : std_logic_vector(1 downto 0);

    -- 模式00: seg_decoder
    signal sd_seg : std_logic_vector(6 downto 0);

    -- 模式01: hello_display
    signal hd_hex3, hd_hex2, hd_hex1, hd_hex0 : std_logic_vector(6 downto 0);

    -- 模式10: hex_scan
    signal hs_hex0, hs_hex1, hs_hex2, hs_hex3 : std_logic_vector(6 downto 0);
    signal hs_hex4, hs_hex5, hs_hex6, hs_hex7 : std_logic_vector(6 downto 0);

    -- 模式11: digital_clock
    signal dc_hex7, dc_hex6, dc_hex5, dc_hex4 : std_logic_vector(6 downto 0);
    signal dc_hex3, dc_hex2, dc_hex1, dc_hex0 : std_logic_vector(6 downto 0);
    signal dc_ledr_mode   : std_logic_vector(1 downto 0);
    signal dc_ledr_alarm  : std_logic;
    signal dc_ledr_bcd_hi : std_logic_vector(3 downto 0);
    signal dc_ledr_bcd_lo : std_logic_vector(3 downto 0);
    signal dc_ledg        : std_logic_vector(7 downto 0);

    -- 合并输出
    signal hex_out : std_logic_vector(55 downto 0);

    constant BLANK : std_logic_vector(6 downto 0) := "1111111";
begin
    mode <= SW(17) & SW(16);

    -- ===== 模式00: seg_decoder =====
    u_seg_decoder : entity work.seg_decoder
        port map(
            A0  => SW(0),
            A1  => SW(1),
            A2  => SW(2),
            seg => sd_seg
        );

    -- ===== 模式01: hello_display =====
    u_hello : entity work.hello_display
        port map(
            A0   => SW(0),
            A1   => SW(1),
            A2   => SW(2),
            hex3 => hd_hex3,
            hex2 => hd_hex2,
            hex1 => hd_hex1,
            hex0 => hd_hex0
        );

    -- ===== 模式10: hex_scan =====
    u_hex_scan : entity work.hex_scan
        port map(
            clk      => CLOCK_50,
            reset    => '1',
            seg_out0 => hs_hex0,
            seg_out1 => hs_hex1,
            seg_out2 => hs_hex2,
            seg_out3 => hs_hex3,
            seg_out4 => hs_hex4,
            seg_out5 => hs_hex5,
            seg_out6 => hs_hex6,
            seg_out7 => hs_hex7
        );

    -- ===== 模式11: digital_clock =====
    u_clock : entity work.digital_clock
        port map(
            clk          => CLOCK_50,
            reset_n      => KEY_N(3),
            sw_mode      => SW(15 downto 14),
            sw_alarm_en  => SW(13),
            sw_bcd_hi    => SW(7 downto 4),
            sw_bcd_lo    => SW(3 downto 0),
            key_n        => KEY_N(2 downto 0),
            hex7         => dc_hex7,
            hex6         => dc_hex6,
            hex5         => dc_hex5,
            hex4         => dc_hex4,
            hex3         => dc_hex3,
            hex2         => dc_hex2,
            hex1         => dc_hex1,
            hex0         => dc_hex0,
            ledr_mode    => dc_ledr_mode,
            ledr_alarm   => dc_ledr_alarm,
            ledr_bcd_hi  => dc_ledr_bcd_hi,
            ledr_bcd_lo  => dc_ledr_bcd_lo,
            ledg         => dc_ledg
        );

    -- ===== 模式路由: HEX =====
    process(mode, sd_seg, hd_hex3, hd_hex2, hd_hex1, hd_hex0,
            hs_hex7, hs_hex6, hs_hex5, hs_hex4, hs_hex3, hs_hex2, hs_hex1, hs_hex0,
            dc_hex7, dc_hex6, dc_hex5, dc_hex4, dc_hex3, dc_hex2, dc_hex1, dc_hex0)
    begin
        case mode is
            when "00" =>
                hex_out(6 downto 0)   <= sd_seg;
                hex_out(13 downto 7)  <= BLANK;
                hex_out(20 downto 14) <= BLANK;
                hex_out(27 downto 21) <= BLANK;
                hex_out(34 downto 28) <= BLANK;
                hex_out(41 downto 35) <= BLANK;
                hex_out(48 downto 42) <= BLANK;
                hex_out(55 downto 49) <= BLANK;

            when "01" =>
                hex_out(6 downto 0)   <= hd_hex0;
                hex_out(13 downto 7)  <= hd_hex1;
                hex_out(20 downto 14) <= hd_hex2;
                hex_out(27 downto 21) <= hd_hex3;
                hex_out(34 downto 28) <= BLANK;
                hex_out(41 downto 35) <= BLANK;
                hex_out(48 downto 42) <= BLANK;
                hex_out(55 downto 49) <= BLANK;

            when "10" =>
                hex_out(6 downto 0)   <= hs_hex0;
                hex_out(13 downto 7)  <= hs_hex1;
                hex_out(20 downto 14) <= hs_hex2;
                hex_out(27 downto 21) <= hs_hex3;
                hex_out(34 downto 28) <= hs_hex4;
                hex_out(41 downto 35) <= hs_hex5;
                hex_out(48 downto 42) <= hs_hex6;
                hex_out(55 downto 49) <= hs_hex7;

            when others =>
                hex_out(6 downto 0)   <= dc_hex0;
                hex_out(13 downto 7)  <= dc_hex1;
                hex_out(20 downto 14) <= dc_hex2;
                hex_out(27 downto 21) <= dc_hex3;
                hex_out(34 downto 28) <= dc_hex4;
                hex_out(41 downto 35) <= dc_hex5;
                hex_out(48 downto 42) <= dc_hex6;
                hex_out(55 downto 49) <= dc_hex7;
        end case;
    end process;

    HEX <= hex_out;

    -- ===== LEDR 路由: 仅模式11有效，其余全灭 =====
    process(mode, dc_ledr_mode, dc_ledr_alarm, dc_ledr_bcd_hi, dc_ledr_bcd_lo)
    begin
        if mode = "11" then
            LEDR(17 downto 16) <= (others => '0');
            LEDR(15 downto 14) <= dc_ledr_mode;
            LEDR(13)           <= dc_ledr_alarm;
            LEDR(12 downto 8)  <= (others => '0');
            LEDR(7 downto 4)   <= dc_ledr_bcd_hi;
            LEDR(3 downto 0)   <= dc_ledr_bcd_lo;
        else
            LEDR <= (others => '0');  -- 全灭
        end if;
    end process;

    -- ===== LEDG 路由: 仅模式11有效，其余全灭 =====
    process(mode, dc_ledg)
    begin
        if mode = "11" then
            LEDG(7 downto 0) <= dc_ledg;
            LEDG(8)          <= '0';  -- LEDG8 不再单独使用
        else
            LEDG <= (others => '0');  -- 全灭
        end if;
    end process;

end behavioral;
