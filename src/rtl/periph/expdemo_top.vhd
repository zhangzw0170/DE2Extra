-- expdemo_top.vhd — Hardware experiment multiplexer
--
-- Instantiates all experiment adapters, muxes their outputs
-- based on the channel register from expdemo_wb.
--
-- Channel mapping (channel == experiment number):
--   0 = shell pass-through (outputs zeroed)
--   1 = Exp1 (3-8 decoder)
--   2 = Exp2 (LED patterns)
--   3 = Exp3 (7-seg display)
--   4 = Exp4 (RAM)
--   5 = Exp5 (FSM)
--   6 = Exp6 (VGA static test patterns)
--   7 = Exp7 (VGA animated test patterns)
--   8 = Exp8 (PS/2 keyboard)
--   9 = Exp9 (UART)
--  10 = Exp10 (IR NEC)
--  11 = Exp11 (DDS)
--  12 = Exp12 (Simple CPU)
--  13 = Exp13a (LCD SOC)

library ieee;
use ieee.std_logic_1164.all;
use work.de2extra_pkg.all;

entity expdemo_top is
    port (
        clk_i       : in  std_logic;
        rst_n_i     : in  std_logic;

        -- shared inputs (all experiments see these)
        sw          : in  std_logic_vector(17 downto 0);
        key_n       : in  std_logic_vector(3 downto 0);

        -- dedicated inputs (for experiments that need them)
        ps2_clk_i   : in  std_logic;
        ps2_dat_i   : in  std_logic;
        uart_rxd_i  : in  std_logic;
        uart_txd_o  : out std_logic;
        irda_rxd_i  : in  std_logic;

        -- muxed outputs (routed to board)
        hex_o       : out std_logic_vector(55 downto 0);
        ledr_o      : out std_logic_vector(17 downto 0);
        ledg_o      : out std_logic_vector(8 downto 0);
        lcd_data_o  : out std_logic_vector(7 downto 0);
        lcd_rs_o    : out std_logic;
        lcd_rw_o    : out std_logic;
        lcd_en_o    : out std_logic;

        -- active flag (high when channel /= 0)
        active_o    : out std_logic;
        channel_o   : out integer range 0 to 13;

        -- VGA output (active when channel = 6 or 7)
        vga_r_o     : out std_logic_vector(7 downto 0);
        vga_g_o     : out std_logic_vector(7 downto 0);
        vga_b_o     : out std_logic_vector(7 downto 0);
        vga_hs_o    : out std_logic;
        vga_vs_o    : out std_logic;
        vga_clk_o   : out std_logic;
        vga_blank_o : out std_logic;
        vga_sync_o  : out std_logic;
        vga_en_o    : out std_logic;

        -- Wishbone slave
        wb_adr_i    : in  std_logic_vector(2 downto 0);
        wb_dat_i    : in  std_logic_vector(31 downto 0);
        wb_dat_o    : out std_logic_vector(31 downto 0);
        wb_we_i     : in  std_logic;
        wb_stb_i    : in  std_logic;
        wb_ack_o    : out std_logic
    );
end entity expdemo_top;

architecture rtl of expdemo_top is
    signal channel : integer range 0 to 13;
    signal active  : std_logic;
    signal exp2_selected : std_logic;
    signal exp12_selected : std_logic;
    signal exp13_selected : std_logic;

    -- experiment outputs
    signal out_1, out_2, out_3, out_4, out_5   : exp_out_t;
    signal out_6, out_7, out_8, out_9, out_10  : exp_out_t;
    signal out_11                               : exp_out_t;
    signal out_12, out_13a                      : exp_out_t;
    signal exp12_pc    : std_logic_vector(7 downto 0);
    signal exp12_ac    : std_logic_vector(15 downto 0);
    signal exp12_ir    : std_logic_vector(15 downto 0);
    signal exp12_step  : std_logic_vector(7 downto 0);
    signal exp12_fsm   : std_logic_vector(3 downto 0);
    signal exp12_auto  : std_logic;
    signal exp12_detail : std_logic;
    signal exp13_msg_sel : std_logic_vector(1 downto 0);
    signal exp13_scroll  : std_logic_vector(5 downto 0);

    -- Exp6/7 VGA signals
    signal vga6_r, vga6_g, vga6_b   : std_logic_vector(7 downto 0);
    signal vga6_hs, vga6_vs         : std_logic;
    signal vga6_clk, vga6_blank     : std_logic;
    signal vga6_sync                : std_logic;
    signal vga7_r, vga7_g, vga7_b   : std_logic_vector(7 downto 0);
    signal vga7_hs, vga7_vs         : std_logic;
    signal vga7_clk, vga7_blank     : std_logic;
    signal vga7_sync                : std_logic;

    -- Exp9 UART TXD
    signal exp9_txd : std_logic;

    -- Exp8 exit monitor: Del make code = E0 71, release = E0 F0 71.
    signal ps2_mon_clk_fall : std_logic;
    signal ps2_mon_dat_sync : std_logic;
    signal ps2_mon_scan     : std_logic_vector(7 downto 0);
    signal ps2_mon_valid    : std_logic;
    signal ps2_break_seen   : std_logic := '0';

    -- Exp10 exit monitor: MENU = 0x11 on the Exp10 remote profile.
    signal ir_mon_valid : std_logic;
    signal ir_mon_cmd   : std_logic_vector(7 downto 0);

    signal force_shell  : std_logic := '0';
begin

    -- WB slave: channel register
    u_wb : entity work.expdemo_wb
        port map (
            clk_i     => clk_i,
            rst_n_i   => rst_n_i,
            force_shell_i => force_shell,
            exp12_pc_i     => exp12_pc,
            exp12_fsm_i    => exp12_fsm,
            exp12_auto_i   => exp12_auto,
            exp12_detail_i => exp12_detail,
            exp12_ac_i     => exp12_ac,
            exp12_ir_i     => exp12_ir,
            exp12_step_i   => exp12_step,
            exp13_msg_sel_i => exp13_msg_sel,
            exp13_scroll_i  => exp13_scroll,
            channel_o => channel,
            active_o  => active,
            wb_adr_i  => wb_adr_i,
            wb_dat_i  => wb_dat_i,
            wb_dat_o  => wb_dat_o,
            wb_we_i   => wb_we_i,
            wb_stb_i  => wb_stb_i,
            wb_ack_o  => wb_ack_o
        );

    active_o <= active;
    channel_o <= channel;
    exp2_selected <= '1' when channel = 2 else '0';
    exp12_selected <= '1' when channel = 12 else '0';
    exp13_selected <= '1' when channel = 13 else '0';

    -- Exp8 Del exit monitor
    u_ps2_mon_sync : entity work.exp8_ps2_sync
        port map (
            clk      => clk_i,
            ps2_clk  => ps2_clk_i,
            ps2_dat  => ps2_dat_i,
            clk_fall => ps2_mon_clk_fall,
            dat_sync => ps2_mon_dat_sync
        );

    u_ps2_mon_rx : entity work.exp8_ps2_receiver
        port map (
            clk       => clk_i,
            clk_fall  => ps2_mon_clk_fall,
            dat_sync  => ps2_mon_dat_sync,
            scan_code => ps2_mon_scan,
            valid     => ps2_mon_valid
        );

    -- Exp10 MENU exit monitor
    u_ir_menu_mon : entity work.ir_dbg_exp10
        port map (
            clk_i      => clk_i,
            rst_n_i    => rst_n_i,
            irda_rxd_i => irda_rxd_i,
            valid_o    => ir_mon_valid,
            cmd_o      => ir_mon_cmd
        );

    p_exit_mon : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                force_shell  <= '0';
                ps2_break_seen <= '0';
            else
                force_shell <= '0';

                if channel /= 8 then
                    ps2_break_seen <= '0';
                elsif ps2_mon_valid = '1' then
                    if ps2_mon_scan = x"F0" then
                        ps2_break_seen <= '1';
                    elsif (ps2_mon_scan = x"71") and (ps2_break_seen = '0') then
                        force_shell <= '1';
                        ps2_break_seen <= '0';
                    else
                        ps2_break_seen <= '0';
                    end if;
                end if;

                if (channel = 10) and (ir_mon_valid = '1') and (ir_mon_cmd = x"11") then
                    force_shell <= '1';
                end if;
            end if;
        end if;
    end process;

    -- Exp1: 3-8 Decoder (pure combinational)
    u_e1 : entity work.adapt_exp1
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n, exp_out => out_1);

    -- Exp2: LED patterns
    u_e2 : entity work.adapt_exp2
        port map (clk_50 => clk_i, rst_n => rst_n_i, selected_i => exp2_selected,
                  sw => sw, key_n => key_n, exp_out => out_2);

    -- Exp3: 7-seg display
    u_e3 : entity work.adapt_exp3
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n, exp_out => out_3);

    -- Exp4: RAM
    u_e4 : entity work.adapt_exp4
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n, exp_out => out_4);

    -- Exp5: FSM
    u_e5 : entity work.adapt_exp5
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n, exp_out => out_5);

    -- Exp6: VGA static test patterns
    u_e6 : entity work.adapt_exp6
        port map (
            clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n,
            exp_out => out_6,
            vga_r => vga6_r, vga_g => vga6_g, vga_b => vga6_b,
            vga_hs => vga6_hs, vga_vs => vga6_vs,
            vga_clk => vga6_clk, vga_blank => vga6_blank, vga_sync => vga6_sync
        );

    -- Exp7: VGA animated test patterns
    u_e7 : entity work.adapt_exp7
        port map (
            clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n,
            exp_out => out_7,
            vga_r => vga7_r, vga_g => vga7_g, vga_b => vga7_b,
            vga_hs => vga7_hs, vga_vs => vga7_vs,
            vga_clk => vga7_clk, vga_blank => vga7_blank, vga_sync => vga7_sync
        );

    -- Exp8: PS/2 keyboard
    u_e8 : entity work.adapt_exp8
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n,
                  ps2_clk => ps2_clk_i, ps2_dat => ps2_dat_i, exp_out => out_8);

    -- Exp9: UART
    u_e9 : entity work.adapt_exp9
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n,
                  uart_txd => exp9_txd, uart_rxd => uart_rxd_i, exp_out => out_9);

    -- Exp10: IR NEC
    u_e10 : entity work.adapt_exp10
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n,
                  irda_rxd => irda_rxd_i, exp_out => out_10);

    -- Exp11: DDS
    u_e11 : entity work.adapt_exp11
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n, exp_out => out_11);

    -- Exp12: Simple CPU
    u_e12 : entity work.adapt_exp12
        port map (
            clk_50     => clk_i,
            rst_n      => rst_n_i,
            selected_i => exp12_selected,
            sw         => sw,
            key_n      => key_n,
            exp_out    => out_12,
            pc_o       => exp12_pc,
            ac_o       => exp12_ac,
            ir_o       => exp12_ir,
            step_o     => exp12_step,
            auto_o     => exp12_auto,
            detail_o   => exp12_detail,
            fsm_o      => exp12_fsm
        );

    -- Exp13a: LCD SOC
    u_e13a : entity work.adapt_exp13a
        port map (
            clk_50     => clk_i,
            rst_n      => rst_n_i,
            selected_i => exp13_selected,
            sw         => sw,
            key_n      => key_n,
            exp_out    => out_13a,
            msg_sel_o  => exp13_msg_sel,
            scroll_o   => exp13_scroll
        );

    -- Exp9 UART TXD output (only when channel=9)
    uart_txd_o <= exp9_txd when channel = 9 else '1';

    -- Output mux
    p_mux : process(channel, out_1, out_2, out_3, out_4, out_5,
                   out_6, out_7, out_8, out_9, out_10, out_11,
                   out_12, out_13a)
    begin
        -- default: shell mode (all outputs zeroed)
        hex_o      <= (others => '1');
        ledr_o     <= (others => '0');
        ledg_o     <= (others => '0');
        lcd_data_o <= (others => '0');
        lcd_rs_o   <= '0';
        lcd_rw_o   <= '0';
        lcd_en_o   <= '0';

        case channel is
            when 1  => hex_o <= out_1.hex;  ledr_o <= out_1.ledr; ledg_o <= out_1.ledg;
            when 2  => hex_o <= out_2.hex;  ledr_o <= out_2.ledr; ledg_o <= out_2.ledg;
            when 3  => hex_o <= out_3.hex;  ledr_o <= out_3.ledr; ledg_o <= out_3.ledg;
            when 4  => hex_o <= out_4.hex;  ledr_o <= out_4.ledr; ledg_o <= out_4.ledg;
            when 5  => hex_o <= out_5.hex;  ledr_o <= out_5.ledr; ledg_o <= out_5.ledg;
            when 6  => hex_o <= out_6.hex;  ledr_o <= out_6.ledr; ledg_o <= out_6.ledg;
            when 7  => hex_o <= out_7.hex;  ledr_o <= out_7.ledr; ledg_o <= out_7.ledg;
            when 8  => hex_o <= out_8.hex;  ledr_o <= out_8.ledr; ledg_o <= out_8.ledg;
            when 9  => hex_o <= out_9.hex;  ledr_o <= out_9.ledr; ledg_o <= out_9.ledg;
            when 10 => hex_o <= out_10.hex; ledr_o <= out_10.ledr; ledg_o <= out_10.ledg;
            when 11 => hex_o <= out_11.hex; ledr_o <= out_11.ledr; ledg_o <= out_11.ledg;
            when 12 =>
                hex_o <= out_12.hex; ledr_o <= out_12.ledr; ledg_o <= out_12.ledg;
                lcd_data_o <= out_12.lcd_data;
                lcd_rs_o   <= out_12.lcd_rs;
                lcd_rw_o   <= out_12.lcd_rw;
                lcd_en_o   <= out_12.lcd_en;
            when 13 =>
                hex_o <= out_13a.hex; ledr_o <= out_13a.ledr; ledg_o <= out_13a.ledg;
                lcd_data_o <= out_13a.lcd_data;
                lcd_rs_o   <= out_13a.lcd_rs;
                lcd_rw_o   <= out_13a.lcd_rw;
                lcd_en_o   <= out_13a.lcd_en;
            when others =>
                null;  -- channel=0: shell pass-through
        end case;
    end process;

    -- VGA output mux: route Exp6 or Exp7 VGA signals based on channel
    vga_en_o <= '1' when (channel = 6 or channel = 7) else '0';

    vga_r_o     <= vga6_r     when channel = 6 else
                   vga7_r     when channel = 7 else (others => '0');
    vga_g_o     <= vga6_g     when channel = 6 else
                   vga7_g     when channel = 7 else (others => '0');
    vga_b_o     <= vga6_b     when channel = 6 else
                   vga7_b     when channel = 7 else (others => '0');
    vga_hs_o    <= vga6_hs    when channel = 6 else
                   vga7_hs    when channel = 7 else '1';
    vga_vs_o    <= vga6_vs    when channel = 6 else
                   vga7_vs    when channel = 7 else '1';
    vga_clk_o   <= vga6_clk   when channel = 6 else
                   vga7_clk   when channel = 7 else '0';
    vga_blank_o <= vga6_blank when channel = 6 else
                   vga7_blank when channel = 7 else '0';
    vga_sync_o  <= vga6_sync  when channel = 6 else
                   vga7_sync  when channel = 7 else '0';

end architecture rtl;
