-- expdemo_wb.vhd — ExpDemo Wishbone Slave (channel register)
--
-- Register map (word-addressed, 4-byte aligned):
--   0x00  CHANNEL (R/W)  — active experiment channel (0=shell, 1-13=exp, 6/7=reserved)
--   0x04  STATUS  (R)    — [0]=active, [7:4]=channel id

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity expdemo_wb is
    port (
        clk_i      : in  std_logic;
        rst_n_i    : in  std_logic;
        force_shell_i : in std_logic;

        -- channel output (to expdemo_top mux)
        channel_o  : out integer range 0 to 13;
        active_o   : out std_logic;

        -- Wishbone slave
        wb_adr_i   : in  std_logic_vector(2 downto 0);
        wb_dat_i   : in  std_logic_vector(31 downto 0);
        wb_dat_o   : out std_logic_vector(31 downto 0);
        wb_we_i    : in  std_logic;
        wb_stb_i   : in  std_logic;
        wb_ack_o   : out std_logic
    );
end entity expdemo_wb;

architecture rtl of expdemo_wb is
    signal channel : integer range 0 to 13 := 0;
    signal ack     : std_logic;
begin

    channel_o <= channel;
    active_o  <= '1' when (channel /= 0) and (channel /= 6) and (channel /= 7) else '0';

    p_reg : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                channel <= 0;
                ack     <= '0';
            else
                if force_shell_i = '1' then
                    channel <= 0;
                else
                    -- write CHANNEL
                    if wb_stb_i = '1' and wb_we_i = '1' and wb_adr_i = "000" then
                        if unsigned(wb_dat_i(3 downto 0)) <= 13 and
                           wb_dat_i(3 downto 0) /= "0110" and
                           wb_dat_i(3 downto 0) /= "0111" then
                            channel <= to_integer(unsigned(wb_dat_i(3 downto 0)));
                        end if;
                    end if;
                end if;

                -- single-cycle ack
                ack <= wb_stb_i and not ack;
            end if;
        end if;
    end process;

    -- read mux
    process(all)
    begin
        wb_dat_o <= (others => '0');
        if wb_stb_i = '1' and wb_we_i = '0' then
            case wb_adr_i is
                when "000" =>   -- 0x00: CHANNEL
                    wb_dat_o(3 downto 0) <= std_logic_vector(to_unsigned(channel, 4));
                when "001" =>   -- 0x04: STATUS
                    if channel /= 0 then
                        wb_dat_o(0) <= '1';
                    end if;
                    wb_dat_o(7 downto 4) <= std_logic_vector(to_unsigned(channel, 4));
                when others =>
                    null;
            end case;
        end if;
    end process;

    wb_ack_o <= ack;

end architecture rtl;
