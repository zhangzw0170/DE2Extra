-- ir_nec_wb.vhd — IR NEC Decoder with Wishbone Register Interface
--
-- Wraps ir_nec_decoder (Exp10) and exposes decoded NEC commands as
-- memory-mapped registers at ADDR_IR_BASE (0xF0009000).
--
-- Register Map (byte offsets):
--   0x00  DATA (R)   — [7:0]=cmd, [15:8]=addr_hi
--   0x04  STATUS (R) — [0]=valid (sticky), [1]=repeat (pulse)
--              (W)   — write 0x00000000 to clear valid bit
--
-- Usage:
--   while (STATUS & 1) == 0 { }      // wait for valid
--   cmd = DATA & 0xFF;               // read command byte
--   STATUS = 0;                      // clear valid for next command

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ir_nec_wb is
    port (
        clk_i        : in  std_logic;
        rst_n_i      : in  std_logic;
        irda_rxd_i   : in  std_logic;

        -- Wishbone slave (32-bit, byte-addressed)
        wb_adr_i     : in  std_logic_vector(2 downto 0);
        wb_dat_i     : in  std_logic_vector(31 downto 0);
        wb_dat_o     : out std_logic_vector(31 downto 0);
        wb_we_i      : in  std_logic;
        wb_stb_i     : in  std_logic;
        wb_ack_o     : out std_logic
    );
end entity ir_nec_wb;

architecture rtl of ir_nec_wb is

    -- IR decoder signals
    signal dec_cmd       : std_logic_vector(7 downto 0);
    signal dec_addr      : std_logic_vector(15 downto 0);
    signal dec_valid     : std_logic;
    signal dec_repeat    : std_logic;
    signal dec_count     : std_logic_vector(7 downto 0);

    -- Register storage
    signal reg_data      : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_valid     : std_logic := '0';
    signal reg_repeat    : std_logic := '0';

    -- Write acknowledge
    signal ack           : std_logic;

begin

    -- ================================================================
    -- IR NEC decoder (pure hardware, always running)
    -- ================================================================
    u_decoder : entity work.ir_nec_decoder
        port map (
            clk_i        => clk_i,
            rst_n_i      => rst_n_i,
            irda_rxd_i   => irda_rxd_i,
            cmd_o        => dec_cmd,
            addr_o       => dec_addr,
            valid_o      => dec_valid,
            repeat_o     => dec_repeat,
            cmd_count_o  => dec_count
        );

    -- ================================================================
    -- Latch decoded command on valid pulse
    -- ================================================================
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                reg_data  <= (others => '0');
                reg_valid <= '0';
                reg_repeat <= '0';
            else
                if dec_valid = '1' then
                    reg_data  <= dec_addr(15 downto 8) & dec_cmd;
                    reg_valid <= '1';
                end if;
                if dec_repeat = '1' then
                    reg_repeat <= '1';
                end if;

                -- Clear valid on write to STATUS register
                if wb_stb_i = '1' and wb_we_i = '1' and wb_adr_i = "100" then
                    if wb_dat_i(0) = '0' then
                        reg_valid <= '0';
                    end if;
                    if wb_dat_i(1) = '0' then
                        reg_repeat <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ================================================================
    -- Wishbone read mux
    -- ================================================================
    process(all)
    begin
        wb_dat_o <= (others => '0');

        if wb_stb_i = '1' and wb_we_i = '0' then
            case wb_adr_i is
                when "000" =>   -- 0x00: DATA
                    wb_dat_o <= x"0000" & reg_data;
                when "100" =>   -- 0x04: STATUS
                    wb_dat_o <= (others => '0');
                    wb_dat_o(1) <= reg_repeat;
                    wb_dat_o(0) <= reg_valid;
                when others =>
                    wb_dat_o <= (others => '0');
            end case;
        end if;
    end process;

    -- ================================================================
    -- Wishbone acknowledge
    -- ================================================================
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                ack <= '0';
            else
                ack <= wb_stb_i and not ack;  -- single-cycle ack
            end if;
        end if;
    end process;

    wb_ack_o <= ack;

end architecture rtl;
