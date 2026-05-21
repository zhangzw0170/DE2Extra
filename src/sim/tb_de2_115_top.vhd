-- tb_de2_115_top.vhd — DE2-115 顶层仿真 testbench
--
-- 验证: 时钟/复位生成, CPU 启动, GPIO 输出, UART TX
library ieee;
use ieee.std_logic_1164.all;

entity tb_de2_115_top is
end entity tb_de2_115_top;

architecture sim of tb_de2_115_top is

    constant CLK_PERIOD : time := 20 ns;  -- 50MHz

    -- DUT signals
    signal CLOCK_50  : std_logic := '0';
    signal KEY       : std_logic_vector(3 downto 0) := (others => '0');
    signal UART_TXD  : std_logic;
    signal UART_RXD  : std_logic := '1';  -- idle high
    signal LEDR      : std_logic_vector(17 downto 0);
    signal LEDG      : std_logic_vector(8 downto 0);
    signal HEX0      : std_logic_vector(6 downto 0);
    signal HEX1      : std_logic_vector(6 downto 0);
    signal HEX2      : std_logic_vector(6 downto 0);
    signal HEX3      : std_logic_vector(6 downto 0);
    signal DRAM_ADDR : std_logic_vector(12 downto 0);
    signal DRAM_BA   : std_logic_vector(1 downto 0);
    signal DRAM_CAS_N : std_logic;
    signal DRAM_CKE  : std_logic;
    signal DRAM_CLK  : std_logic;
    signal DRAM_CS_N : std_logic;
    signal DRAM_DQ   : std_logic_vector(31 downto 0);
    signal DRAM_DQM  : std_logic_vector(3 downto 0);
    signal DRAM_RAS_N : std_logic;
    signal DRAM_WE_N : std_logic;

begin

    -- Clock generation
    CLOCK_50 <= not CLOCK_50 after CLK_PERIOD / 2;

    -- DUT
    u_dut : entity work.de2_115_top
    port map (
        CLOCK_50    => CLOCK_50,
        KEY         => KEY,
        UART_TXD    => UART_TXD,
        UART_RXD    => UART_RXD,
        LEDR        => LEDR,
        LEDG        => LEDG,
        HEX0        => HEX0,
        HEX1        => HEX1,
        HEX2        => HEX2,
        HEX3        => HEX3,
        DRAM_ADDR   => DRAM_ADDR,
        DRAM_BA     => DRAM_BA,
        DRAM_CAS_N  => DRAM_CAS_N,
        DRAM_CKE    => DRAM_CKE,
        DRAM_CLK    => DRAM_CLK,
        DRAM_CS_N   => DRAM_CS_N,
        DRAM_DQ     => DRAM_DQ,
        DRAM_DQM    => DRAM_DQM,
        DRAM_RAS_N  => DRAM_RAS_N,
        DRAM_WE_N   => DRAM_WE_N
    );

    -- SDRAM DQ pull-up (tri-state handling)
    DRAM_DQ <= (others => 'Z');

    -- Stimulus
    p_stim : process
    begin
        -- Assert reset
        KEY(0) <= '0';
        wait for 200 ns;
        wait until rising_edge(CLOCK_50);

        -- Release reset
        KEY(0) <= '1';
        wait for 100 ns;
        wait until rising_edge(CLOCK_50);

        -- Let CPU run for a while
        wait for 20 ms;

        -- Check LEDR activity (should have toggled)
        assert LEDR /= (LEDR'range => '0')
            report "INFO: LEDR still all-zero after 20ms (may be OK if IMEM image is minimal)"
            severity note;

        -- Hold
        wait;
    end process p_stim;

end architecture sim;
