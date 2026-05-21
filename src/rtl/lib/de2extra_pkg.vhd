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
    constant ADDR_SDRAM_BASE  : std_logic_vector(31 downto 0) := x"01000000";
    constant ADDR_PERIPH_BASE : std_logic_vector(31 downto 0) := x"F0000000";
    constant ADDR_PERIPH_SIZE : natural := 16#1000#;  -- 4KB per peripheral slot

    -- Peripheral address offsets (index into periph space)
    constant PERIPH_VGA       : natural := 16#000#;
    constant PERIPH_PS2_KBD   : natural := 16#001#;
    constant PERIPH_PS2_MOUSE : natural := 16#002#;
    constant PERIPH_TIMER     : natural := 16#003#;
    constant PERIPH_IRQ_CTRL  : natural := 16#004#;
    constant PERIPH_SPI_SD    : natural := 16#005#;
    constant PERIPH_I2C       : natural := 16#006#;
    constant PERIPH_AUDIO     : natural := 16#007#;
    constant PERIPH_LCD       : natural := 16#008#;
    constant PERIPH_IR        : natural := 16#009#;
    constant PERIPH_ETH       : natural := 16#00A#;
    constant PERIPH_GPIO_EXT  : natural := 16#00B#;

    -- ================================================================
    -- Generic register interface (platform-agnostic peripheral bus)
    -- ================================================================
    type reg_req_t is record
        cs      : std_logic;
        wr_en   : std_logic;
        rd_en   : std_logic;
        addr    : std_logic_vector(3 downto 0);
        wr_data : std_logic_vector(31 downto 0);
    end record;

    type reg_rsp_t is record
        rd_data : std_logic_vector(31 downto 0);
        irq     : std_logic;
    end record;

    constant REG_REQ_IDLE : reg_req_t := (
        cs      => '0',
        wr_en   => '0',
        rd_en   => '0',
        addr    => (others => '0'),
        wr_data => (others => '0')
    );

    constant REG_RSP_NULL : reg_rsp_t := (
        rd_data => (others => '0'),
        irq     => '0'
    );

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
