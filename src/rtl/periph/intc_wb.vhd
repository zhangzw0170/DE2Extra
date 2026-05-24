-- intc_wb.vhd — Interrupt Controller (3-channel)
--
-- Collects up to 3 IRQ sources into a single MEI output.
-- Software reads PENDING to discover which sources fired,
-- writes MASK to enable/disable individual channels.
--
-- Register Map (word-addressed, 4-byte aligned):
--   0x00  PENDING (R)  — latched pending IRQs (read-after-clear)
--   0x04  MASK (R/W)   — per-channel enable mask

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity intc_wb is
    port (
        clk_i   : in  std_logic;
        rst_n_i : in  std_logic;
        irq_i   : in  std_logic_vector(2 downto 0);
        irq_o   : out std_logic;

        -- Wishbone slave
        wb_adr_i    : in  std_logic_vector(2 downto 0);
        wb_dat_i    : in  std_logic_vector(31 downto 0);
        wb_dat_o    : out std_logic_vector(31 downto 0);
        wb_we_i     : in  std_logic;
        wb_stb_i    : in  std_logic;
        wb_ack_o    : out std_logic
    );
end entity intc_wb;

architecture rtl of intc_wb is
    signal pending : std_logic_vector(2 downto 0) := "000";
    signal mask    : std_logic_vector(2 downto 0) := "000";
    signal ack     : std_logic;
begin

    -- Latch pending: any unmasked irq_i bit sets corresponding pending bit
    p_latch : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                pending <= (others => '0');
            else
                pending <= pending or (irq_i and mask);
                -- read-clear: reading PENDING clears it
                if wb_stb_i = '1' and wb_we_i = '0' and wb_adr_i = "000" then
                    pending <= (others => '0');
                end if;
            end if;
        end if;
    end process;

    -- MEI output: any pending+masked bit
    irq_o <= '1' when (pending and mask) /= "000" else '0';

    -- Read mux
    process(all)
    begin
        wb_dat_o <= (others => '0');
        if wb_we_i = '0' then
            case wb_adr_i is
                when "000" =>   -- 0x00: PENDING
                    wb_dat_o <= x"0000000" & "0" & pending;
                when "001" =>   -- 0x04: MASK
                    wb_dat_o <= x"0000000" & "0" & mask;
                when others =>
                    null;
            end case;
        end if;
    end process;

    -- Write + ack
    p_wb : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                ack  <= '0';
                mask <= (others => '0');
            else
                ack <= wb_stb_i and not ack;

                if wb_stb_i = '1' and wb_we_i = '1' and wb_adr_i = "001" then
                    mask <= wb_dat_i(2 downto 0);
                end if;
            end if;
        end if;
    end process;

    wb_ack_o <= ack;

end architecture rtl;
