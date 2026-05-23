-- de2extra_pkg.vhd — DE2Extra 共享类型、常量和工具函数
library ieee;
use ieee.std_logic_1164.all;

package de2extra_pkg is

    -- ================================================================
    -- Clock constants
    -- ================================================================
    constant CLK_50MHZ   : natural := 50_000_000;
    constant CLK_100MHZ  : natural := 100_000_000;

    -- ================================================================
    -- Address space (used by Wishbone interconnect in Phase 1)
    -- ================================================================
    constant ADDR_SDRAM_BASE   : std_logic_vector(31 downto 0) := x"01000000"; -- 128MB
    constant ADDR_VGA_BASE     : std_logic_vector(31 downto 0) := x"F0000000"; -- 8KB
    constant ADDR_PS2_BASE     : std_logic_vector(31 downto 0) := x"F0002000"; -- 4KB
    constant ADDR_TIMER_BASE   : std_logic_vector(31 downto 0) := x"F0004000"; -- 4KB
    constant ADDR_INTC_BASE    : std_logic_vector(31 downto 0) := x"F0006000"; -- 4KB
    constant ADDR_LCD_BASE     : std_logic_vector(31 downto 0) := x"F0008000"; -- 4KB
    constant ADDR_IR_BASE      : std_logic_vector(31 downto 0) := x"F0009000"; -- 4KB
    constant ADDR_DDS_BASE     : std_logic_vector(31 downto 0) := x"F000A000"; -- 4KB
    constant ADDR_SD_BASE      : std_logic_vector(31 downto 0) := x"F000B000"; -- 4KB
    -- ================================================================
    -- Seven-segment display utility
    -- ================================================================
    -- Common-anode, active-low: segment order gfedcba
    function hex_to_seg7 (hex : std_logic_vector(3 downto 0))
        return std_logic_vector;

end package de2extra_pkg;

package body de2extra_pkg is

    function hex_to_seg7 (hex : std_logic_vector(3 downto 0))
        return std_logic_vector is
        -- Returns [6:0] = gfedcba, active-low (0 = ON)
        variable seg : std_logic_vector(6 downto 0);
    begin
        case hex is
            when x"0" => seg := "1000000";
            when x"1" => seg := "1111001";
            when x"2" => seg := "0100100";
            when x"3" => seg := "0110000";
            when x"4" => seg := "0011001";
            when x"5" => seg := "0010010";
            when x"6" => seg := "0000010";
            when x"7" => seg := "1111000";
            when x"8" => seg := "0000000";
            when x"9" => seg := "0010000";
            when x"A" => seg := "0001000";
            when x"B" => seg := "0000011";
            when x"C" => seg := "1000110";
            when x"D" => seg := "0100001";
            when x"E" => seg := "0000110";
            when x"F" => seg := "0001110";
            when others => seg := "1111111";  -- blank
        end case;
        return seg;
    end function hex_to_seg7;

end package body de2extra_pkg;
