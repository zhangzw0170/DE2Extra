-- de2_115_top.vhd — DE2-115 板级顶层实体
--
-- 唯一知道板级引脚的模块。职责:
--   1. 实例化时钟/复位生成 (clk_rst_gen)
--   2. 实例化 CPU (neorv32_wrapper)
--   3. 实例化七段管映射 (seg7_mapper)
--   4. 信号路由: GPIO ↔ LED/HEX, UART ↔ RS-232
--   5. 未使用引脚安全处理
--
-- 换板子: 新建 xxx_top.vhd 替换此文件，其他模块不动。
library ieee;
use ieee.std_logic_1164.all;

entity de2_115_top is
    port (
        -- 时钟
        CLOCK_50    : in  std_logic;

        -- 按键 (active-low)
        KEY         : in  std_logic_vector(3 downto 0);

        -- UART (RS-232, 3.3V LVTTL)
        UART_TXD    : out std_logic;
        UART_RXD    : in  std_logic;

        -- LED
        LEDR        : out std_logic_vector(17 downto 0);
        LEDG        : out std_logic_vector(8 downto 0);

        -- 七段数码管 (active-low, gfedcba)
        HEX0        : out std_logic_vector(6 downto 0);
        HEX1        : out std_logic_vector(6 downto 0);
        HEX2        : out std_logic_vector(6 downto 0);
        HEX3        : out std_logic_vector(6 downto 0);

        -- SDRAM (Phase 1 启用, 当前悬空)
        DRAM_ADDR   : out std_logic_vector(12 downto 0);
        DRAM_BA     : out std_logic_vector(1 downto 0);
        DRAM_CAS_N  : out std_logic;
        DRAM_CKE    : out std_logic;
        DRAM_CLK    : out std_logic;
        DRAM_CS_N   : out std_logic;
        DRAM_DQ     : inout std_logic_vector(31 downto 0);
        DRAM_DQM    : out std_logic_vector(3 downto 0);
        DRAM_RAS_N  : out std_logic;
        DRAM_WE_N   : out std_logic
    );
end entity de2_115_top;

architecture rtl of de2_115_top is

    -- Clock/reset
    signal clk_50m     : std_logic;
    signal clk_vga     : std_logic;
    signal rst_n       : std_logic;

    -- CPU ↔ 外部
    signal gpio_out    : std_logic_vector(31 downto 0);
    signal gpio_in     : std_logic_vector(31 downto 0);

    -- XBUS (Phase 0 未使用)
    signal xbus_adr    : std_logic_vector(31 downto 0);
    signal xbus_dat_o  : std_logic_vector(31 downto 0);
    signal xbus_we     : std_logic;
    signal xbus_sel    : std_logic_vector(3 downto 0);
    signal xbus_stb    : std_logic;
    signal xbus_cyc    : std_logic;

    -- 七段管显示数据 (来自 GPIO 高位)
    signal hex_display : std_logic_vector(15 downto 0);

begin

    -- ================================================================
    -- Clock and Reset Generation
    -- ================================================================
    u_clk_rst : entity work.clk_rst_gen
    port map (
        clk_50m_i   => CLOCK_50,
        rst_key_n_i => KEY(0),
        clk_50m_o   => clk_50m,
        clk_vga_o   => clk_vga,
        rst_n_o     => rst_n
    );

    -- ================================================================
    -- NEORV32 CPU
    -- ================================================================
    u_cpu : entity work.neorv32_wrapper
    generic map (
        CLOCK_FREQUENCY => 50_000_000,
        IMEM_SIZE       => 32*1024,
        DMEM_SIZE       => 16*1024,
        BOOT_MODE       => 2          -- IMEM image (上电即跑)
    )
    port map (
        clk_i       => clk_50m,
        rst_n_i     => rst_n,
        -- UART
        uart_txd_o  => UART_TXD,
        uart_rxd_i  => UART_RXD,
        -- GPIO
        gpio_o      => gpio_out,
        gpio_i      => gpio_in,
        -- JTAG (Quartus 自动连接 USB-Blaster)
        jtag_tck_i  => '0',
        jtag_tdi_i  => '0',
        jtag_tdo_o  => open,
        jtag_tms_i  => '0',
        -- XBUS (Phase 0: 无外设, 返回 error)
        xbus_adr_o  => xbus_adr,
        xbus_dat_o  => xbus_dat_o,
        xbus_dat_i  => (others => '0'),
        xbus_we_o   => xbus_we,
        xbus_sel_o  => xbus_sel,
        xbus_stb_o  => xbus_stb,
        xbus_cyc_o  => xbus_cyc,
        xbus_ack_i  => '0',
        xbus_err_i  => xbus_stb and xbus_cyc  -- 总线错误: 告知 CPU 无此设备
    );

    -- ================================================================
    -- GPIO → LED 映射
    -- ================================================================
    -- LEDR[17:0] ← GPIO 输出低 18 位
    LEDR <= gpio_out(17 downto 0);

    -- LEDG 用作状态指示:
    --   LEDG[0] = 复位状态 (rst_n 取反, 复位时亮)
    --   LEDG[7:1] 悬空
    LEDG(0) <= not rst_n;
    LEDG(8 downto 1) <= (others => '0');

    -- GPIO 输入 (高位, 可接拨码开关等, Phase 0 暂不使用)
    gpio_in <= (others => '0');

    -- ================================================================
    -- GPIO → 七段数码管映射
    -- ================================================================
    -- GPIO[31:16] 的 16 位拆为 4 个 nibble → HEX0..3
    -- (与 LEDR[17:0] 不重叠, 避免互相干扰)
    hex_display <= gpio_out(31 downto 16);

    u_seg7 : entity work.seg7_mapper
    port map (
        hex_nibbles => hex_display,
        seg0        => HEX0,
        seg1        => HEX1,
        seg2        => HEX2,
        seg3        => HEX3
    );

    -- ================================================================
    -- SDRAM: Phase 0 悬空 (安全输出)
    -- ================================================================
    DRAM_ADDR   <= (others => 'Z');
    DRAM_BA     <= (others => 'Z');
    DRAM_CAS_N  <= '1';
    DRAM_CKE    <= '0';
    DRAM_CLK    <= '0';
    DRAM_CS_N   <= '1';
    DRAM_DQ     <= (others => 'Z');
    DRAM_DQM    <= (others => '1');
    DRAM_RAS_N  <= '1';
    DRAM_WE_N   <= '1';

end architecture rtl;
