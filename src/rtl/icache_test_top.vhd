-- icache_test_top.vhd — Minimal ICACHE test: CPU + SDRAM + VGA only
--
-- Stripped-down version of de2os_top for ICACHE bring-up testing.
-- Only 2 Wishbone slaves: SDRAM + VGA text/pixel terminal.
-- ICACHE enabled with burst support.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.de2extra_pkg.all;
use work.build_info_pkg.all;

entity icache_test_top is
    port (
        CLOCK_50    : in  std_logic;
        KEY         : in  std_logic_vector(3 downto 0);
        UART_TXD    : out std_logic;
        UART_RXD    : in  std_logic;
        LEDR        : out std_logic_vector(17 downto 0);
        LEDG        : out std_logic_vector(8 downto 0);

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

        VGA_R       : out std_logic_vector(7 downto 0);
        VGA_G       : out std_logic_vector(7 downto 0);
        VGA_B       : out std_logic_vector(7 downto 0);
        VGA_HS      : out std_logic;
        VGA_VS      : out std_logic;
        VGA_CLK     : out std_logic;
        VGA_SYNC_N  : out std_logic;
        VGA_BLANK_N : out std_logic
    );
end entity icache_test_top;

architecture rtl of icache_test_top is

    -- Clock/reset
    signal clk_50m         : std_logic;
    signal clk_sdram       : std_logic;
    signal clk_sdram_shift : std_logic;
    signal rst_n           : std_logic;
    signal rst_sdram_n     : std_logic;
    signal rst_sdram_sync  : std_logic_vector(1 downto 0);

    -- CPU GPIO
    signal gpio_out : std_logic_vector(31 downto 0);
    signal gpio_in  : std_logic_vector(31 downto 0);

    -- XBUS
    signal xbus_adr   : std_logic_vector(31 downto 0);
    signal xbus_dat_o : std_logic_vector(31 downto 0);
    signal xbus_dat_i : std_logic_vector(31 downto 0);
    signal xbus_we    : std_logic;
    signal xbus_sel   : std_logic_vector(3 downto 0);
    signal xbus_stb   : std_logic;
    signal xbus_cyc   : std_logic;
    signal xbus_ack   : std_logic;
    signal xbus_err   : std_logic;
    signal xbus_cti   : std_logic_vector(2 downto 0);
    signal xbus_tag   : std_logic_vector(2 downto 0);

    -- SDRAM Wishbone
    signal sdram_wb_adr  : std_logic_vector(24 downto 0);
    signal sdram_wb_dat_o : std_logic_vector(31 downto 0);
    signal sdram_wb_dat_i : std_logic_vector(31 downto 0);
    signal sdram_wb_we   : std_logic;
    signal sdram_wb_sel  : std_logic_vector(3 downto 0);
    signal sdram_wb_stb  : std_logic;
    signal sdram_wb_cyc  : std_logic;
    signal sdram_wb_ack  : std_logic;
    signal sdram_wb_cti  : std_logic_vector(2 downto 0);

    -- VGA terminal register interface (combined text + pixel)
    signal vga_reg_adr   : std_logic_vector(15 downto 0);
    signal vga_reg_dat_o : std_logic_vector(31 downto 0);
    signal vga_reg_dat_i : std_logic_vector(31 downto 0);
    signal vga_reg_we    : std_logic;
    signal vga_reg_stb   : std_logic;
    signal vga_reg_ack   : std_logic;

    -- VGA text terminal split
    signal vga_txt_reg_dat_i : std_logic_vector(31 downto 0);
    signal vga_txt_reg_stb   : std_logic;
    signal vga_txt_reg_ack   : std_logic;

    -- VGA pixel controller split
    signal vga_px_reg_adr    : std_logic_vector(15 downto 0);
    signal vga_px_reg_dat_i  : std_logic_vector(31 downto 0);
    signal vga_px_reg_dat_o  : std_logic_vector(31 downto 0);
    signal vga_px_reg_we     : std_logic;
    signal vga_px_reg_stb    : std_logic;
    signal vga_px_reg_ack    : std_logic;

    -- VGA physical outputs
    signal vga_r_int      : std_logic_vector(7 downto 0);
    signal vga_g_int      : std_logic_vector(7 downto 0);
    signal vga_b_int      : std_logic_vector(7 downto 0);
    signal vga_hs_int     : std_logic;
    signal vga_vs_int     : std_logic;
    signal vga_clk_int    : std_logic;
    signal vga_sync_int   : std_logic;
    signal vga_blank_int  : std_logic;

    -- VGA pixel mode signals
    signal vga_pixel_r     : std_logic_vector(7 downto 0);
    signal vga_pixel_g     : std_logic_vector(7 downto 0);
    signal vga_pixel_b     : std_logic_vector(7 downto 0);
    signal vga_pixel_hs    : std_logic;
    signal vga_pixel_vs    : std_logic;
    signal vga_pixel_blank : std_logic;
    signal vga_pixel_sync  : std_logic;
    signal vga_pixel_clk   : std_logic;
    signal vga_pixel_mode  : std_logic;

    -- VGA pixel SDRAM read port
    signal vga_sdram_rd_adr   : std_logic_vector(24 downto 0);
    signal vga_sdram_rd_req   : std_logic;
    signal vga_sdram_rd_data  : std_logic_vector(31 downto 0);
    signal vga_sdram_rd_valid : std_logic;
    signal vga_sdram_rd_done  : std_logic;

begin

    -- ================================================================
    -- Clock & Reset
    -- ================================================================
    u_clk_rst : entity work.clk_rst_gen
    port map (
        clk_50m_i   => CLOCK_50,
        rst_key_n_i => KEY(0),
        clk_50m_o   => clk_50m,
        clk_sdram_o => clk_sdram,
        clk_sdram_shift_o => clk_sdram_shift,
        clk_vga_o   => open,
        rst_n_o     => rst_n,
        pll_locked_o => open
    );

    p_rst_sdram_sync : process (clk_sdram, rst_n)
    begin
        if rst_n = '0' then
            rst_sdram_sync <= (others => '0');
        elsif rising_edge(clk_sdram) then
            rst_sdram_sync <= rst_sdram_sync(0) & '1';
        end if;
    end process;
    rst_sdram_n <= rst_sdram_sync(1);

    -- ================================================================
    -- NEORV32 CPU — ICACHE ENABLED with burst
    -- ================================================================
    u_cpu : entity work.neorv32_wrapper
    generic map (
        CLOCK_FREQUENCY => 50_000_000,
        IMEM_SIZE       => 16*1024,
        DMEM_SIZE       => 16*1024,
        BOOT_MODE       => 0,
        ICACHE_EN       => false,
        ICACHE_BLOCKS   => 64,
        ICACHE_BLOCK_SZ => 32,
        ICACHE_BURSTS   => true,
        TRNG_EN         => true
    )
    port map (
        clk_i       => clk_50m,
        rst_n_i     => rst_n,
        uart_txd_o  => UART_TXD,
        uart_rxd_i  => UART_RXD,
        gpio_o      => gpio_out,
        gpio_i      => gpio_in,
        jtag_tck_i  => '0',
        jtag_tdi_i  => '0',
        jtag_tdo_o  => open,
        jtag_tms_i  => '0',
        xbus_adr_o  => xbus_adr,
        xbus_dat_o  => xbus_dat_o,
        xbus_dat_i  => xbus_dat_i,
        xbus_we_o   => xbus_we,
        xbus_sel_o  => xbus_sel,
        xbus_stb_o  => xbus_stb,
        xbus_cyc_o  => xbus_cyc,
        xbus_ack_i  => xbus_ack,
        xbus_err_i  => xbus_err,
        xbus_cti_o  => xbus_cti,
        xbus_tag_o  => xbus_tag,
        irq_mei_i   => '0'
    );

    -- ================================================================
    -- Wishbone Interconnect (2 slaves only)
    -- ================================================================
    u_intercon : entity work.wb_intercon_icache
    port map (
        m_adr_i  => xbus_adr,
        m_dat_i  => xbus_dat_o,
        m_dat_o  => xbus_dat_i,
        m_we_i   => xbus_we,
        m_sel_i  => xbus_sel,
        m_stb_i  => xbus_stb,
        m_cyc_i  => xbus_cyc,
        m_ack_o  => xbus_ack,
        m_err_o  => xbus_err,
        m_cti_i  => xbus_cti,
        s0_adr_o => sdram_wb_adr,
        s0_dat_i => sdram_wb_dat_i,
        s0_dat_o => sdram_wb_dat_o,
        s0_we_o  => sdram_wb_we,
        s0_sel_o => sdram_wb_sel,
        s0_stb_o => sdram_wb_stb,
        s0_cyc_o => sdram_wb_cyc,
        s0_ack_i => sdram_wb_ack,
        s0_cti_o => sdram_wb_cti,
        s1_adr_o => vga_reg_adr,
        s1_dat_i => vga_reg_dat_i,
        s1_dat_o => vga_reg_dat_o,
        s1_we_o  => vga_reg_we,
        s1_stb_o => vga_reg_stb,
        s1_ack_i => vga_reg_ack
    );

    -- ================================================================
    -- SDRAM Controller
    -- ================================================================
    u_sdram : entity work.sdram_ctrl
    port map (
        clk_cpu_i   => clk_50m,
        rst_n_i     => rst_n,
        wb_adr_i    => sdram_wb_adr,
        wb_dat_i    => sdram_wb_dat_o,
        wb_dat_o    => sdram_wb_dat_i,
        wb_we_i     => sdram_wb_we,
        wb_sel_i    => sdram_wb_sel,
        wb_stb_i    => sdram_wb_stb,
        wb_cyc_i    => sdram_wb_cyc,
        wb_ack_o    => sdram_wb_ack,
        wb_err_o    => open,
        wb_cti_i    => sdram_wb_cti,
        clk_sdram_i => clk_sdram,
        rst_sdram_n => rst_sdram_n,
        dram_addr   => DRAM_ADDR,
        dram_ba     => DRAM_BA,
        dram_cas_n  => DRAM_CAS_N,
        dram_cke    => DRAM_cke,
        dram_cs_n   => DRAM_CS_N,
        dram_dq     => DRAM_DQ,
        dram_dqm    => DRAM_DQM,
        dram_ras_n  => DRAM_RAS_N,
        dram_we_n   => DRAM_WE_N,
        vga_rd_adr_i  => vga_sdram_rd_adr,
        vga_rd_req_i  => vga_sdram_rd_req,
        vga_rd_data_o => vga_sdram_rd_data,
        vga_rd_valid_o=> vga_sdram_rd_valid,
        vga_rd_done_o => vga_sdram_rd_done
    );

    DRAM_CLK <= clk_sdram_shift;

    -- ================================================================
    -- VGA Text Terminal + Pixel Controller
    -- ================================================================

    -- Split VGA register space: <0x7000 → text, >=0x7000 → pixel
    vga_txt_reg_stb <= vga_reg_stb when unsigned(vga_reg_adr) < to_unsigned(16#7000#, 16) else '0';
    vga_px_reg_stb  <= vga_reg_stb when unsigned(vga_reg_adr) >= to_unsigned(16#7000#, 16) else '0';
    vga_px_reg_adr  <= std_logic_vector(unsigned(vga_reg_adr) - to_unsigned(16#7000#, 16));
    vga_px_reg_dat_o <= vga_reg_dat_o;
    vga_px_reg_we    <= vga_reg_we;
    vga_reg_dat_i    <= vga_px_reg_dat_i when unsigned(vga_reg_adr) >= to_unsigned(16#7000#, 16) else vga_txt_reg_dat_i;
    vga_reg_ack      <= vga_px_reg_ack when unsigned(vga_reg_adr) >= to_unsigned(16#7000#, 16) else vga_txt_reg_ack;

    u_vga : entity work.vga_text_terminal
    port map (
        clk_50m_i   => clk_50m,
        rst_n_i     => rst_n,
        vga_r_o     => vga_r_int,
        vga_g_o     => vga_g_int,
        vga_b_o     => vga_b_int,
        vga_hs_o    => vga_hs_int,
        vga_vs_o    => vga_vs_int,
        vga_blank_o => vga_blank_int,
        vga_sync_o  => vga_sync_int,
        vga_clk_o   => vga_clk_int,
        reg_adr_i   => vga_reg_adr,
        reg_dat_i   => vga_reg_dat_o,
        reg_dat_o   => vga_txt_reg_dat_i,
        reg_we_i    => vga_reg_we,
        reg_stb_i   => vga_txt_reg_stb,
        reg_ack_o   => vga_txt_reg_ack
    );

    u_vga_px : entity work.vga_pixel_ctrl
    port map (
        clk_50m_i    => clk_50m,
        rst_n_i      => rst_n,
        vga_r_o      => vga_pixel_r,
        vga_g_o      => vga_pixel_g,
        vga_b_o      => vga_pixel_b,
        vga_hs_o     => vga_pixel_hs,
        vga_vs_o     => vga_pixel_vs,
        vga_blank_o  => vga_pixel_blank,
        vga_sync_o   => vga_pixel_sync,
        vga_clk_o    => vga_pixel_clk,
        reg_adr_i    => vga_px_reg_adr,
        reg_dat_i    => vga_px_reg_dat_o,
        reg_dat_o    => vga_px_reg_dat_i,
        reg_we_i     => vga_px_reg_we,
        reg_stb_i    => vga_px_reg_stb,
        reg_ack_o    => vga_px_reg_ack,
        mode_en_o    => vga_pixel_mode,
        vga_rd_adr_o => vga_sdram_rd_adr,
        vga_rd_req_o => vga_sdram_rd_req,
        vga_rd_data_i => vga_sdram_rd_data,
        vga_rd_valid_i => vga_sdram_rd_valid,
        vga_rd_done_i  => vga_sdram_rd_done
    );

    -- VGA output mux: pixel mode overrides text
    VGA_R       <= vga_pixel_r    when vga_pixel_mode = '1' else vga_r_int;
    VGA_G       <= vga_pixel_g    when vga_pixel_mode = '1' else vga_g_int;
    VGA_B       <= vga_pixel_b    when vga_pixel_mode = '1' else vga_b_int;
    VGA_HS      <= vga_pixel_hs   when vga_pixel_mode = '1' else vga_hs_int;
    VGA_VS      <= vga_pixel_vs   when vga_pixel_mode = '1' else vga_vs_int;
    VGA_CLK     <= vga_pixel_clk  when vga_pixel_mode = '1' else vga_clk_int;
    VGA_SYNC_N  <= vga_pixel_sync when vga_pixel_mode = '1' else vga_sync_int;
    VGA_BLANK_N <= vga_pixel_blank when vga_pixel_mode = '1' else vga_blank_int;

    -- ================================================================
    -- GPIO / LED debug
    -- ================================================================
    LEDR <= "00" & gpio_out(15 downto 0);
    LEDG <= (not rst_n) & gpio_out(23 downto 16);
    gpio_in <= (others => '0');

end architecture rtl;
