-- de2_115_top.vhd — DE2-115 板级顶层实体
--
-- 唯一知道板级引脚的模块。职责:
--   1. 实例化时钟/复位生成 (clk_rst_gen)
--   2. 实例化 CPU (neorv32_wrapper)
--   3. 实例化 Wishbone 总线互连 (wb_intercon)
--   4. 实例化 SDRAM 控制器 (sdram_ctrl)
--   5. 实例化七段管映射 (seg7_mapper)
--   6. 信号路由: GPIO ↔ LED/HEX, UART ↔ RS-232
--
-- 新外设: 在 wb_intercon 中添加 slave 端口 + 地址解码。
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.de2extra_pkg.all;
library jtag_uart_0;

entity de2_115_top is
    port (
        -- 时钟
        CLOCK_50    : in  std_logic;

        -- 按键 (active-low)
        KEY         : in  std_logic_vector(3 downto 0);

        -- UART (RS-232, 3.3V LVTTL)
        UART_TXD    : out std_logic;
        UART_RXD    : in  std_logic;

        -- PS/2 keyboard
        PS2_CLK     : inout std_logic;
        PS2_DAT     : inout std_logic;

        -- LED
        LEDR        : out std_logic_vector(17 downto 0);
        LEDG        : out std_logic_vector(8 downto 0);

        -- 拨码开关
        SW          : in  std_logic_vector(17 downto 0);

        -- 七段数码管 (active-low, gfedcba)
        HEX0        : out std_logic_vector(6 downto 0);
        HEX1        : out std_logic_vector(6 downto 0);
        HEX2        : out std_logic_vector(6 downto 0);
        HEX3        : out std_logic_vector(6 downto 0);
        HEX4        : out std_logic_vector(6 downto 0);
        HEX5        : out std_logic_vector(6 downto 0);
        HEX6        : out std_logic_vector(6 downto 0);
        HEX7        : out std_logic_vector(6 downto 0);

        -- SDRAM
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

        -- LCD (HD44780, 16x2)
        LCD_DATA    : out std_logic_vector(7 downto 0);
        LCD_RS      : out std_logic;
        LCD_RW      : out std_logic;
        LCD_EN      : out std_logic;
        LCD_ON      : out std_logic;
        LCD_BLON    : out std_logic;

        -- IR receiver (NEC protocol)
        IRDA_RXD    : in  std_logic;

        -- VGA
        VGA_R       : out std_logic_vector(7 downto 0);
        VGA_G       : out std_logic_vector(7 downto 0);
        VGA_B       : out std_logic_vector(7 downto 0);
        VGA_HS      : out std_logic;
        VGA_VS      : out std_logic;
        VGA_CLK     : out std_logic;
        VGA_SYNC_N  : out std_logic;
        VGA_BLANK_N : out std_logic
    );
end entity de2_115_top;

architecture rtl of de2_115_top is

    -- Clock/reset
    signal clk_50m     : std_logic;
    signal clk_sdram   : std_logic;
    signal clk_sdram_shift : std_logic;
    signal rst_n       : std_logic;
    signal rst_sdram_n : std_logic;
    signal rst_sdram_sync : std_logic_vector(1 downto 0);

    -- CPU <-> 外部
    signal gpio_out    : std_logic_vector(31 downto 0);
    signal gpio_in     : std_logic_vector(31 downto 0);
    signal uart_txd_int : std_logic;

    -- XBUS
    signal xbus_adr    : std_logic_vector(31 downto 0);
    signal xbus_dat_o  : std_logic_vector(31 downto 0);
    signal xbus_we     : std_logic;
    signal xbus_sel    : std_logic_vector(3 downto 0);
    signal xbus_stb    : std_logic;
    signal xbus_cyc    : std_logic;
    signal xbus_dat_i  : std_logic_vector(31 downto 0);
    signal xbus_ack    : std_logic;
    signal xbus_err    : std_logic;

    -- SDRAM Wishbone
    signal sdram_wb_adr  : std_logic_vector(24 downto 0);
    signal sdram_wb_dat_o : std_logic_vector(31 downto 0);
    signal sdram_wb_dat_i : std_logic_vector(31 downto 0);
    signal sdram_wb_we   : std_logic;
    signal sdram_wb_sel  : std_logic_vector(3 downto 0);
    signal sdram_wb_stb  : std_logic;
    signal sdram_wb_cyc  : std_logic;
    signal sdram_wb_ack  : std_logic;

    -- VGA terminal register interface
    signal vga_reg_adr   : std_logic_vector(15 downto 0);
    signal vga_reg_dat_o : std_logic_vector(31 downto 0);
    signal vga_reg_dat_i : std_logic_vector(31 downto 0);
    signal vga_reg_we    : std_logic;
    signal vga_reg_stb   : std_logic;
    signal vga_reg_ack   : std_logic;

    -- PS/2 controller register interface
    signal ps2_reg_adr   : std_logic_vector(3 downto 0);
    signal ps2_reg_dat_o : std_logic_vector(31 downto 0);
    signal ps2_reg_dat_i : std_logic_vector(31 downto 0);
    signal ps2_reg_we    : std_logic;
    signal ps2_reg_stb   : std_logic;
    signal ps2_reg_ack   : std_logic;
    signal ps2_irq       : std_logic;
    signal ps2_valid     : std_logic;
    signal ps2_scancode  : std_logic_vector(7 downto 0);
    signal ps2_clk_oe    : std_logic;
    signal ps2_dat_oe    : std_logic;
    -- VGA physical outputs
    signal vga_r_int     : std_logic_vector(7 downto 0);
    signal vga_g_int     : std_logic_vector(7 downto 0);
    signal vga_b_int     : std_logic_vector(7 downto 0);
    signal vga_hs_int    : std_logic;
    signal vga_vs_int    : std_logic;
    signal vga_clk_int   : std_logic;
    signal vga_sync_int  : std_logic;
    signal vga_blank_int : std_logic;

    -- LCD mux (SW16=0: status, SW16=1: 2b debug)
    signal lcd_status_data  : std_logic_vector(7 downto 0);
    signal lcd_status_rs    : std_logic;
    signal lcd_status_rw    : std_logic;
    signal lcd_status_en    : std_logic;
    signal lcd_status_on    : std_logic;
    signal lcd_status_blon  : std_logic;
    signal lcd_debug_data   : std_logic_vector(7 downto 0);
    signal lcd_debug_rs     : std_logic;
    signal lcd_debug_rw     : std_logic;
    signal lcd_debug_en     : std_logic;
    signal lcd_debug_on     : std_logic;
    signal lcd_debug_blon   : std_logic;
    signal sw16_meta        : std_logic := '0';
    signal sw16_sel         : std_logic := '0';
    signal lcd_status_rst_n : std_logic;
    signal lcd_debug_rst_n  : std_logic;
    signal expdemo_active_d : std_logic := '0';
    signal lcd_shell_rst_cnt : integer range 0 to 50000 := 50000;

    -- IR receiver Wishbone
    signal ir_wb_adr   : std_logic_vector(2 downto 0);
    signal ir_wb_dat_o : std_logic_vector(31 downto 0);
    signal ir_wb_dat_i : std_logic_vector(31 downto 0);
    signal ir_wb_we    : std_logic;
    signal ir_wb_stb   : std_logic;
    signal ir_wb_ack   : std_logic;

    -- IR debug: parallel Exp10-style decoder for A/B test
    signal dbg_ir_valid : std_logic;
    signal dbg_ir_cmd   : std_logic_vector(7 downto 0);
    signal dbg_ir_toggle : std_logic := '0';

    -- Timer @ 0xF0004000
    signal tmr_wb_adr   : std_logic_vector(2 downto 0);
    signal tmr_wb_dat_o : std_logic_vector(31 downto 0);
    signal tmr_wb_dat_i : std_logic_vector(31 downto 0);
    signal tmr_wb_we    : std_logic;
    signal tmr_wb_stb   : std_logic;
    signal tmr_wb_ack   : std_logic;
    signal tmr_irq      : std_logic;

    -- INTC @ 0xF0006000
    signal intc_wb_adr   : std_logic_vector(2 downto 0);
    signal intc_wb_dat_o : std_logic_vector(31 downto 0);
    signal intc_wb_dat_i : std_logic_vector(31 downto 0);
    signal intc_wb_we    : std_logic;
    signal intc_wb_stb   : std_logic;
    signal intc_wb_ack   : std_logic;
    signal intc_irq      : std_logic;

    -- NTT accelerator Wishbone
    signal ntt_wb_adr   : std_logic_vector(11 downto 0);
    signal ntt_wb_dat_o : std_logic_vector(31 downto 0);
    signal ntt_wb_dat_i : std_logic_vector(31 downto 0);
    signal ntt_wb_we    : std_logic;
    signal ntt_wb_stb   : std_logic;
    signal ntt_wb_ack   : std_logic;

    -- LCD Wishbone (stub — not used in de2shell)
    signal lcd_wb_adr   : std_logic_vector(3 downto 0);
    signal lcd_wb_dat_o : std_logic_vector(31 downto 0);
    signal lcd_wb_dat_i : std_logic_vector(31 downto 0);
    signal lcd_wb_we    : std_logic;
    signal lcd_wb_stb   : std_logic;
    signal lcd_wb_ack   : std_logic;

    -- ExpDemo Wishbone
    signal expdemo_wb_adr   : std_logic_vector(2 downto 0);
    signal expdemo_wb_dat_o : std_logic_vector(31 downto 0);
    signal expdemo_wb_dat_i : std_logic_vector(31 downto 0);
    signal expdemo_wb_we    : std_logic;
    signal expdemo_wb_stb   : std_logic;
    signal expdemo_wb_ack   : std_logic;
    signal expdemo_active   : std_logic;
    signal expdemo_channel  : integer range 0 to 13;

    -- ExpDemo board outputs
    signal exp_hex  : std_logic_vector(55 downto 0);
    signal exp_ledr : std_logic_vector(17 downto 0);
    signal exp_ledg : std_logic_vector(8 downto 0);
    signal exp_lcd_data : std_logic_vector(7 downto 0);
    signal exp_lcd_rs   : std_logic;
    signal exp_lcd_rw   : std_logic;
    signal exp_lcd_en   : std_logic;
    signal exp_uart_txd : std_logic;
    signal exp_uart_rxd : std_logic;
    signal ps2_clk_shell_in : std_logic;
    signal ps2_dat_shell_in : std_logic;
    signal ps2_clk_exp_in   : std_logic;
    signal ps2_dat_exp_in   : std_logic;
    signal irda_shell_in    : std_logic;
    signal irda_exp_in      : std_logic;

    -- Shell-mode HEX intermediate signals (before mux)
    signal hex0_shell : std_logic_vector(6 downto 0);
    signal hex1_shell : std_logic_vector(6 downto 0);
    signal hex2_shell : std_logic_vector(6 downto 0);
    signal hex3_shell : std_logic_vector(6 downto 0);
    signal hex4_shell : std_logic_vector(6 downto 0);
    signal hex5_shell : std_logic_vector(6 downto 0);

    -- JTAG UART Avalon bus
    signal jtag_av_cs       : std_logic;
    signal jtag_av_addr     : std_logic;
    signal jtag_av_read_n   : std_logic;
    signal jtag_av_readdata : std_logic_vector(31 downto 0);
    signal jtag_av_write_n  : std_logic;
    signal jtag_av_writedata: std_logic_vector(31 downto 0);
    signal jtag_av_waitreq  : std_logic;

    -- JTAG UART IP (Platform Designer, library jtag_uart_0)
    component jtag_uart_0 is
        port (
            clk_clk                                   : in  std_logic;
            reset_reset_n                             : in  std_logic;
            jtag_uart_0_avalon_jtag_slave_chipselect  : in  std_logic;
            jtag_uart_0_avalon_jtag_slave_address     : in  std_logic;
            jtag_uart_0_avalon_jtag_slave_read_n      : in  std_logic;
            jtag_uart_0_avalon_jtag_slave_readdata    : out std_logic_vector(31 downto 0);
            jtag_uart_0_avalon_jtag_slave_write_n     : in  std_logic;
            jtag_uart_0_avalon_jtag_slave_writedata   : in  std_logic_vector(31 downto 0);
            jtag_uart_0_avalon_jtag_slave_waitrequest : out std_logic
        );
    end component;

begin

    -- ================================================================
    -- Clock and Reset Generation
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

    -- SDRAM 控制器复位在 100MHz 域内同步释放，避免上电时状态机异步出复位
    p_rst_sdram_sync : process (clk_sdram, rst_n)
    begin
        if rst_n = '0' then
            rst_sdram_sync <= (others => '0');
        elsif rising_edge(clk_sdram) then
            rst_sdram_sync <= rst_sdram_sync(0) & '1';
        end if;
    end process;

    rst_sdram_n <= rst_sdram_sync(1);

    p_sw16_sync : process (clk_50m, rst_n)
    begin
        if rst_n = '0' then
            sw16_meta <= '0';
            sw16_sel  <= '0';
        elsif rising_edge(clk_50m) then
            sw16_meta <= SW(16);
            sw16_sel  <= sw16_meta;
        end if;
    end process;

    p_lcd_shell_reinit : process (clk_50m, rst_n)
    begin
        if rst_n = '0' then
            expdemo_active_d <= '0';
            lcd_shell_rst_cnt <= 50000;
        elsif rising_edge(clk_50m) then
            expdemo_active_d <= expdemo_active;
            if (expdemo_active_d = '1') and (expdemo_active = '0') then
                lcd_shell_rst_cnt <= 50000;
            elsif lcd_shell_rst_cnt > 0 then
                lcd_shell_rst_cnt <= lcd_shell_rst_cnt - 1;
            end if;
        end if;
    end process;

    lcd_status_rst_n <= '0' when (rst_n = '0') or (lcd_shell_rst_cnt > 0) else '1';
    lcd_debug_rst_n  <= '0';

    -- Exp8 and Exp10 own PS/2 / IR respectively while active.
    -- Non-exclusive channels leave these inputs connected to the shell side.
    ps2_clk_shell_in <= PS2_CLK when expdemo_channel /= 8 else '1';
    ps2_dat_shell_in <= PS2_DAT when expdemo_channel /= 8 else '1';
    ps2_clk_exp_in   <= PS2_CLK when expdemo_channel = 8 else '1';
    ps2_dat_exp_in   <= PS2_DAT when expdemo_channel = 8 else '1';
    irda_shell_in    <= IRDA_RXD when expdemo_channel /= 10 else '1';
    irda_exp_in      <= IRDA_RXD when expdemo_channel = 10 else '1';

    -- ================================================================
    -- NEORV32 CPU
    -- ================================================================
    u_cpu : entity work.neorv32_wrapper
    generic map (
        CLOCK_FREQUENCY => 50_000_000,
        IMEM_SIZE       => 64*1024,
        DMEM_SIZE       => 16*1024,
        BOOT_MODE       => 2,
        ICACHE_EN       => false
    )
    port map (
        clk_i       => clk_50m,
        rst_n_i     => rst_n,
        uart_txd_o  => uart_txd_int,
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
        xbus_cti_o  => open,
        xbus_tag_o  => open,
        irq_mei_i   => intc_irq
    );

    -- ================================================================
    -- Wishbone Interconnect
    -- ================================================================
    u_intercon : entity work.wb_intercon
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
        m_cti_i  => "000",
        s0_adr_o => sdram_wb_adr,
        s0_dat_i => sdram_wb_dat_i,
        s0_dat_o => sdram_wb_dat_o,
        s0_we_o  => sdram_wb_we,
        s0_sel_o => sdram_wb_sel,
        s0_stb_o => sdram_wb_stb,
        s0_cyc_o => sdram_wb_cyc,
        s0_ack_i => sdram_wb_ack,
        s0_cti_o => open,
        s1_adr_o => vga_reg_adr,
        s1_dat_i => vga_reg_dat_i,
        s1_dat_o => vga_reg_dat_o,
        s1_we_o  => vga_reg_we,
        s1_stb_o => vga_reg_stb,
        s1_ack_i => vga_reg_ack,
        s2_adr_o => ps2_reg_adr,
        s2_dat_i => ps2_reg_dat_i,
        s2_dat_o => ps2_reg_dat_o,
        s2_we_o  => ps2_reg_we,
        s2_stb_o => ps2_reg_stb,
        s2_ack_i => ps2_reg_ack,
        s3_adr_o => ir_wb_adr,
        s3_dat_i => ir_wb_dat_i,
        s3_dat_o => ir_wb_dat_o,
        s3_we_o  => ir_wb_we,
        s3_stb_o => ir_wb_stb,
        s3_ack_i => ir_wb_ack,
        s4_adr_o => ntt_wb_adr,
        s4_dat_i => ntt_wb_dat_i,
        s4_dat_o => ntt_wb_dat_o,
        s4_we_o  => ntt_wb_we,
        s4_stb_o => ntt_wb_stb,
        s4_ack_i => ntt_wb_ack,
        s5_adr_o => lcd_wb_adr,
        s5_dat_i => lcd_wb_dat_i,
        s5_dat_o => lcd_wb_dat_o,
        s5_we_o  => lcd_wb_we,
        s5_stb_o => lcd_wb_stb,
        s5_ack_i => lcd_wb_ack,
        s6_adr_o => tmr_wb_adr,
        s6_dat_i => tmr_wb_dat_i,
        s6_dat_o => tmr_wb_dat_o,
        s6_we_o  => tmr_wb_we,
        s6_stb_o => tmr_wb_stb,
        s6_ack_i => tmr_wb_ack,
        s7_adr_o => intc_wb_adr,
        s7_dat_i => intc_wb_dat_i,
        s7_dat_o => intc_wb_dat_o,
        s7_we_o  => intc_wb_we,
        s7_stb_o => intc_wb_stb,
        s7_ack_i => intc_wb_ack,
        s8_adr_o => expdemo_wb_adr,
        s8_dat_i => expdemo_wb_dat_i,
        s8_dat_o => expdemo_wb_dat_o,
        s8_we_o  => expdemo_wb_we,
        s8_stb_o => expdemo_wb_stb,
        s8_ack_i => expdemo_wb_ack
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
        wb_cti_i    => "000",
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
        dram_we_n   => DRAM_WE_N
    );

    -- DRAM 时钟使用相移版 PLL 输出，给板级地址/命令/写数据留 setup 裕量
    DRAM_CLK <= clk_sdram_shift;

    -- ================================================================
    -- VGA Text Terminal (temporarily disabled to isolate non-VGA bring-up)
    -- ================================================================
    vga_reg_dat_i <= (others => '0');
    vga_reg_ack   <= vga_reg_stb;

    vga_r_int     <= (others => '0');
    vga_g_int     <= (others => '0');
    vga_b_int     <= (others => '0');
    vga_hs_int    <= '1';
    vga_vs_int    <= '0';
    vga_clk_int   <= '0';
    vga_sync_int  <= '0';
    vga_blank_int <= '0';

    VGA_R       <= vga_r_int;
    VGA_G       <= vga_g_int;
    VGA_B       <= vga_b_int;
    VGA_HS      <= vga_hs_int;
    VGA_VS      <= vga_vs_int;
    VGA_CLK     <= vga_clk_int;
    VGA_SYNC_N  <= vga_sync_int;
    VGA_BLANK_N <= vga_blank_int;

    -- ================================================================
    -- PS/2 Keyboard Controller (Phase 2b)
    -- ================================================================
    u_ps2 : entity work.ps2_controller
    port map (
        clk_50m_i   => clk_50m,
        rst_n_i     => rst_n,
        ps2_clk_i   => ps2_clk_shell_in,
        ps2_dat_i   => ps2_dat_shell_in,
        ps2_clk_oe_o => ps2_clk_oe,
        ps2_dat_oe_o => ps2_dat_oe,
        reg_adr_i   => ps2_reg_adr,
        reg_dat_i   => ps2_reg_dat_o,
        reg_dat_o   => ps2_reg_dat_i,
        reg_we_i    => ps2_reg_we,
        reg_stb_i   => ps2_reg_stb,
        reg_ack_o   => ps2_reg_ack,
        ps2_valid_o => ps2_valid,
        ps2_scancode_o => ps2_scancode,
        irq_o       => ps2_irq
    );

    PS2_CLK <= '0' when ps2_clk_oe = '1' else 'Z';
    PS2_DAT <= '0' when ps2_dat_oe = '1' else 'Z';

    -- ================================================================
    -- IR NEC Receiver @ 0xF0009000
    -- ================================================================
    u_ir : entity work.ir_nec_wb
    port map (
        clk_i      => clk_50m,
        rst_n_i    => rst_n,
        irda_rxd_i => irda_shell_in,
        wb_adr_i   => ir_wb_adr,
        wb_dat_i   => ir_wb_dat_o,
        wb_dat_o   => ir_wb_dat_i,
        wb_we_i    => ir_wb_we,
        wb_stb_i   => ir_wb_stb,
        wb_ack_o   => ir_wb_ack
    );

    -- ================================================================
    -- IR debug: parallel Exp10-style decoder for A/B test
    -- gpio_in(30) = exp10_valid, gpio_in(29 downto 22) = exp10_cmd
    -- ================================================================
    u_ir_dbg : entity work.ir_dbg_exp10
        port map (
            clk_i      => clk_50m,
            rst_n_i    => rst_n,
            irda_rxd_i => irda_shell_in,
            valid_o    => dbg_ir_valid,
            cmd_o      => dbg_ir_cmd
        );

    process(clk_50m)
    begin
        if rising_edge(clk_50m) then
            if rst_n = '0' then
                dbg_ir_toggle <= '0';
            elsif dbg_ir_valid = '1' then
                dbg_ir_toggle <= not dbg_ir_toggle;
            end if;
        end if;
    end process;

    gpio_in(30) <= dbg_ir_valid;
    gpio_in(29 downto 22) <= dbg_ir_cmd;

    -- ================================================================
    -- NTT Accelerator @ 0xF000C000
    -- ================================================================
    u_ntt : entity work.ntt_sdf
    port map (
        clk_i    => clk_50m,
        rst_n_i  => rst_n,
        wb_adr_i => ntt_wb_adr,
        wb_dat_i => ntt_wb_dat_o,
        wb_dat_o => ntt_wb_dat_i,
        wb_we_i  => ntt_wb_we,
        wb_stb_i => ntt_wb_stb,
        wb_ack_o => ntt_wb_ack
    );

    -- LCD @ 0xF0008000 (stub — de2shell uses hardware lcd_status/lcd_debug)
    lcd_wb_dat_i <= (others => '0');
    lcd_wb_ack   <= '0';

    -- ================================================================
    -- Timer @ 0xF0004000 — captures IR pulse widths
    -- ================================================================
    u_timer : entity work.timer_wb
    port map (
        clk_i      => clk_50m,
        rst_n_i    => rst_n,
        cap_trig_i => irda_shell_in,
        irq_o      => tmr_irq,
        wb_adr_i   => tmr_wb_adr,
        wb_dat_i   => tmr_wb_dat_o,
        wb_dat_o   => tmr_wb_dat_i,
        wb_we_i    => tmr_wb_we,
        wb_stb_i   => tmr_wb_stb,
        wb_ack_o   => tmr_wb_ack
    );

    -- ================================================================
    -- INTC @ 0xF0006000 — irq_i(0)=IR, (1)=timer, (2)=PS2
    -- ================================================================
    u_intc : entity work.intc_wb
    port map (
        clk_i   => clk_50m,
        rst_n_i => rst_n,
        irq_i   => dbg_ir_valid & tmr_irq & ps2_irq,
        irq_o   => intc_irq,
        wb_adr_i   => intc_wb_adr,
        wb_dat_i   => intc_wb_dat_o,
        wb_dat_o   => intc_wb_dat_i,
        wb_we_i    => intc_wb_we,
        wb_stb_i   => intc_wb_stb,
        wb_ack_o   => intc_wb_ack
    );

    -- ================================================================
    -- ExpDemo: Hardware experiment multiplexer @ 0xF000D000
    -- ================================================================
    u_expdemo : entity work.expdemo_top
    port map (
        clk_i       => clk_50m,
        rst_n_i     => rst_n,
        sw          => SW,
        key_n       => KEY,
        ps2_clk_i   => ps2_clk_exp_in,
        ps2_dat_i   => ps2_dat_exp_in,
        uart_rxd_i  => UART_RXD,
        uart_txd_o  => exp_uart_txd,
        irda_rxd_i  => irda_exp_in,
        hex_o       => exp_hex,
        ledr_o      => exp_ledr,
        ledg_o      => exp_ledg,
        lcd_data_o  => exp_lcd_data,
        lcd_rs_o    => exp_lcd_rs,
        lcd_rw_o    => exp_lcd_rw,
        lcd_en_o    => exp_lcd_en,
        active_o    => expdemo_active,
        channel_o   => expdemo_channel,
        wb_adr_i    => expdemo_wb_adr,
        wb_dat_i    => expdemo_wb_dat_o,
        wb_dat_o    => expdemo_wb_dat_i,
        wb_we_i     => expdemo_wb_we,
        wb_stb_i    => expdemo_wb_stb,
        wb_ack_o    => expdemo_wb_ack
    );

    -- ================================================================
    -- GPIO / ExpDemo -> Board output routing
    -- ================================================================
    -- When expdemo_active: board outputs from expdemo_top
    -- When shell mode (channel=0): board outputs from CPU GPIO + seg7_mapper

    LEDR <= exp_ledr when expdemo_active = '1' else
            gpio_out(15 downto 0) & SW(17 downto 16);

    LEDG <= exp_ledg when expdemo_active = '1' else
            (not rst_n) & gpio_out(23 downto 16);


    gpio_in(17 downto 0)  <= SW;
    gpio_in(20 downto 18) <= not KEY(3 downto 1); -- pressed = '1'
    gpio_in(31) <= dbg_ir_toggle;
    gpio_in(21) <= IRDA_RXD;  -- DEBUG: raw IR signal
    -- gpio_in(30) and (29 downto 22) driven by ir_dbg_exp10
    gpio_in(21) <= IRDA_RXD;  -- DEBUG: expose raw IR signal to GPIO bit 21

    -- ================================================================
    -- GPIO / ExpDemo -> Seven-segment display routing
    -- ================================================================
    u_seg7_lo : entity work.seg7_mapper
    port map (
        hex_nibbles => gpio_out(15 downto 0),
        seg0        => hex0_shell,
        seg1        => hex1_shell,
        seg2        => hex2_shell,
        seg3        => hex3_shell
    );

    u_seg7_hi : entity work.seg7_mapper
    port map (
        hex_nibbles => x"00" & gpio_out(23 downto 16),
        seg0        => hex4_shell,
        seg1        => hex5_shell,
        seg2        => open,
        seg3        => open
    );

    -- Board-level HEX output: mux between shell seg7 and expdemo
    HEX0 <= exp_hex(6 downto 0)   when expdemo_active = '1' else hex0_shell;
    HEX1 <= exp_hex(13 downto 7)  when expdemo_active = '1' else hex1_shell;
    HEX2 <= exp_hex(20 downto 14) when expdemo_active = '1' else hex2_shell;
    HEX3 <= exp_hex(27 downto 21) when expdemo_active = '1' else hex3_shell;
    HEX4 <= exp_hex(34 downto 28) when expdemo_active = '1' else hex4_shell;
    HEX5 <= exp_hex(41 downto 35) when expdemo_active = '1' else hex5_shell;
    HEX6 <= exp_hex(48 downto 42) when expdemo_active = '1' else (others => '1');
    HEX7 <= exp_hex(55 downto 49) when expdemo_active = '1' else (others => '1');

    -- ================================================================
    -- JTAG UART -- CPU 输出通过 JTAG 在 PC 端查看
    -- ================================================================
    UART_TXD <= uart_txd_int;

    u_jtag_uart : component jtag_uart_0
    port map (
        clk_clk                                   => clk_50m,
        reset_reset_n                             => rst_n,
        jtag_uart_0_avalon_jtag_slave_chipselect  => jtag_av_cs,
        jtag_uart_0_avalon_jtag_slave_address     => jtag_av_addr,
        jtag_uart_0_avalon_jtag_slave_read_n      => jtag_av_read_n,
        jtag_uart_0_avalon_jtag_slave_readdata    => jtag_av_readdata,
        jtag_uart_0_avalon_jtag_slave_write_n     => jtag_av_write_n,
        jtag_uart_0_avalon_jtag_slave_writedata   => jtag_av_writedata,
        jtag_uart_0_avalon_jtag_slave_waitrequest => jtag_av_waitreq
    );

    u_jtag_bridge : entity work.uart_jtag_bridge
    generic map (
        CLOCK_FREQ_HZ => 50_000_000,
        BAUD_RATE     => 115200
    )
    port map (
        clk_i          => clk_50m,
        rst_n_i        => rst_n,
        uart_tx_i      => uart_txd_int,
        av_chipselect  => jtag_av_cs,
        av_address     => jtag_av_addr,
        av_read_n      => jtag_av_read_n,
        av_readdata    => jtag_av_readdata,
        av_write_n     => jtag_av_write_n,
        av_writedata   => jtag_av_writedata,
        av_waitrequest => jtag_av_waitreq
    );

    -- ================================================================
    -- LCD -- SW16=0 保持 Phase 1/2a 状态显示; SW16=1 切到 2b 调试显示
    -- ================================================================
    u_lcd_status : entity work.lcd_status
    port map (
        clk_i    => clk_50m,
        rst_n_i  => lcd_status_rst_n,
        gpio_i   => gpio_out,
        lcd_data => lcd_status_data,
        lcd_rs   => lcd_status_rs,
        lcd_rw   => lcd_status_rw,
        lcd_en   => lcd_status_en,
        lcd_on   => lcd_status_on,
        lcd_blon => lcd_status_blon
    );

    u_lcd_debug : entity work.lcd_debug
    port map (
        clk_i       => clk_50m,
        rst_n_i     => lcd_debug_rst_n,
        vga_vs_i    => vga_vs_int,
        ps2_valid_i => ps2_valid,
        ps2_scancode_i => ps2_scancode,
        lcd_data    => lcd_debug_data,
        lcd_rs      => lcd_debug_rs,
        lcd_rw      => lcd_debug_rw,
        lcd_en      => lcd_debug_en,
        lcd_on      => lcd_debug_on,
        lcd_blon    => lcd_debug_blon
    );

    LCD_DATA <= exp_lcd_data when expdemo_active = '1' else lcd_status_data;
    LCD_RS   <= exp_lcd_rs   when expdemo_active = '1' else lcd_status_rs;
    LCD_RW   <= exp_lcd_rw   when expdemo_active = '1' else lcd_status_rw;
    LCD_EN   <= exp_lcd_en   when expdemo_active = '1' else lcd_status_en;
    LCD_ON   <= lcd_status_on;
    LCD_BLON <= lcd_status_blon;

end architecture rtl;
