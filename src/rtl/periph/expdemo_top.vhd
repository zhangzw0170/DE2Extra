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
--   6 = (reserved — VGA)
--   7 = (reserved — VGA)
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

    -- experiment outputs
    signal out_1, out_2, out_3, out_4, out_5   : exp_out_t;
    signal out_8, out_9, out_10, out_11         : exp_out_t;
    signal out_12, out_13a                      : exp_out_t;

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
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n, exp_out => out_2);

    -- Exp3: 7-seg display
    u_e3 : entity work.adapt_exp3
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n, exp_out => out_3);

    -- Exp4: RAM
    u_e4 : entity work.adapt_exp4
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n, exp_out => out_4);

    -- Exp5: FSM
    u_e5 : entity work.adapt_exp5
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n, exp_out => out_5);

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
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n, exp_out => out_12);

    -- Exp13a: LCD SOC
    u_e13a : entity work.adapt_exp13a
        port map (clk_50 => clk_i, rst_n => rst_n_i, sw => sw, key_n => key_n, exp_out => out_13a);

    -- Exp9 UART TXD output (only when channel=9)
    uart_txd_o <= exp9_txd when channel = 9 else '1';

    -- Output mux
    p_mux : process(channel, out_1, out_2, out_3, out_4, out_5,
                   out_8, out_9, out_10, out_11, out_12, out_13a)
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
            -- 6, 7: VGA experiments (reserved/skipped)
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

end architecture rtl;
