-- de2os_imem_top.vhd — V3 bring-up wrapper
--
-- Direct-boot de2shell_rtos from a 128KB IMEM image so VGA shell/UI can be
-- validated without depending on the external RS-232 upload path.
library ieee;
use ieee.std_logic_1164.all;

entity de2os_imem_top is
    port (
        CLOCK_50    : in  std_logic;
        KEY         : in  std_logic_vector(3 downto 0);
        UART_TXD    : out std_logic;
        UART_RXD    : in  std_logic;
        PS2_CLK     : inout std_logic;
        PS2_DAT     : inout std_logic;
        LEDR        : out std_logic_vector(17 downto 0);
        LEDG        : out std_logic_vector(8 downto 0);
        SW          : in  std_logic_vector(17 downto 0);
        HEX0        : out std_logic_vector(6 downto 0);
        HEX1        : out std_logic_vector(6 downto 0);
        HEX2        : out std_logic_vector(6 downto 0);
        HEX3        : out std_logic_vector(6 downto 0);
        HEX4        : out std_logic_vector(6 downto 0);
        HEX5        : out std_logic_vector(6 downto 0);
        HEX6        : out std_logic_vector(6 downto 0);
        HEX7        : out std_logic_vector(6 downto 0);
        DRAM_ADDR   : out std_logic_vector(12 downto 0);
        DRAM_BA     : out std_logic_vector(1 downto 0);
        DRAM_CAS_N  : out std_logic;
        DRAM_cke    : out std_logic;
        DRAM_CLK    : out std_logic;
        DRAM_CS_N   : out std_logic;
        DRAM_DQ     : inout std_logic_vector(31 downto 0);
        DRAM_DQM    : out std_logic_vector(3 downto 0);
        DRAM_RAS_N  : out std_logic;
        DRAM_WE_N   : out std_logic;
        LCD_DATA    : out std_logic_vector(7 downto 0);
        LCD_RS      : out std_logic;
        LCD_RW      : out std_logic;
        LCD_EN      : out std_logic;
        LCD_ON      : out std_logic;
        LCD_BLON    : out std_logic;
        IRDA_RXD    : in  std_logic;
        VGA_R       : out std_logic_vector(7 downto 0);
        VGA_G       : out std_logic_vector(7 downto 0);
        VGA_B       : out std_logic_vector(7 downto 0);
        VGA_HS      : out std_logic;
        VGA_VS      : out std_logic;
        VGA_CLK     : out std_logic;
        VGA_SYNC_N  : out std_logic;
        VGA_BLANK_N : out std_logic;

        -- Audio codec (WM8731) — unused in IMEM bring-up mode
        AUD_XCK     : out std_logic;
        AUD_BCLK    : in  std_logic;
        AUD_DACLRCK : in  std_logic;
        AUD_DACDAT  : out std_logic;
        I2C_SCLK    : out std_logic;
        I2C_SDAT    : inout std_logic
    );
end entity de2os_imem_top;

architecture rtl of de2os_imem_top is
begin

    u_top : entity work.de2os_top
    generic map (
        CPU_IMEM_SIZE_G => 128*1024,
        CPU_BOOT_MODE_G => 2
    )
    port map (
        CLOCK_50    => CLOCK_50,
        KEY         => KEY,
        UART_TXD    => UART_TXD,
        UART_RXD    => UART_RXD,
        PS2_CLK     => PS2_CLK,
        PS2_DAT     => PS2_DAT,
        LEDR        => LEDR,
        LEDG        => LEDG,
        SW          => SW,
        HEX0        => HEX0,
        HEX1        => HEX1,
        HEX2        => HEX2,
        HEX3        => HEX3,
        HEX4        => HEX4,
        HEX5        => HEX5,
        HEX6        => HEX6,
        HEX7        => HEX7,
        DRAM_ADDR   => DRAM_ADDR,
        DRAM_BA     => DRAM_BA,
        DRAM_CAS_N  => DRAM_CAS_N,
        DRAM_cke    => DRAM_cke,
        DRAM_CLK    => DRAM_CLK,
        DRAM_CS_N   => DRAM_CS_N,
        DRAM_DQ     => DRAM_DQ,
        DRAM_DQM    => DRAM_DQM,
        DRAM_RAS_N  => DRAM_RAS_N,
        DRAM_WE_N   => DRAM_WE_N,
        LCD_DATA    => LCD_DATA,
        LCD_RS      => LCD_RS,
        LCD_RW      => LCD_RW,
        LCD_EN      => LCD_EN,
        LCD_ON      => LCD_ON,
        LCD_BLON    => LCD_BLON,
        IRDA_RXD    => IRDA_RXD,
        VGA_R       => VGA_R,
        VGA_G       => VGA_G,
        VGA_B       => VGA_B,
        VGA_HS      => VGA_HS,
        VGA_VS      => VGA_VS,
        VGA_CLK     => VGA_CLK,
        VGA_SYNC_N  => VGA_SYNC_N,
        VGA_BLANK_N => VGA_BLANK_N,
        AUD_XCK     => AUD_XCK,
        AUD_BCLK    => AUD_BCLK,
        AUD_DACLRCK => AUD_DACLRCK,
        AUD_DACDAT  => AUD_DACDAT,
        I2C_SCLK    => I2C_SCLK,
        I2C_SDAT    => I2C_SDAT
    );

end architecture rtl;
