-- timer_wb.vhd — 32-bit Free-Running Timer with Capture
--
-- Captures rising edges on cap_trig_i into a latch. Software reads
-- successive CAPTURE values and computes deltas to decode protocols
-- (e.g. NEC IR). No integer counters — uses unsigned throughout.
--
-- Register Map (word-addressed, 4-byte aligned):
--   0x00  COUNTER (R)  — snapshot of free-running counter
--   0x04  CAPTURE (R)  — counter value at last cap_trig rising edge
--   0x08  CONTROL (R/W)— [0]=capture_en, [1]=irq_en, [2]=cap_flag

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity timer_wb is
    port (
        clk_i       : in  std_logic;
        rst_n_i     : in  std_logic;
        cap_trig_i  : in  std_logic;   -- capture on rising edge
        irq_o       : out std_logic;

        -- Wishbone slave
        wb_adr_i    : in  std_logic_vector(2 downto 0);
        wb_dat_i    : in  std_logic_vector(31 downto 0);
        wb_dat_o    : out std_logic_vector(31 downto 0);
        wb_we_i     : in  std_logic;
        wb_stb_i    : in  std_logic;
        wb_ack_o    : out std_logic
    );
end entity timer_wb;

architecture rtl of timer_wb is
    signal counter    : unsigned(31 downto 0) := (others => '0');
    signal capture    : unsigned(31 downto 0) := (others => '0');
    signal cap_en     : std_logic := '0';
    signal irq_en     : std_logic := '0';
    signal cap_flag   : std_logic := '0';

    -- synchronizer for cap_trig
    signal trig_sync  : std_logic_vector(2 downto 0) := "111";
    signal trig_rise  : std_logic;

    -- wb ack
    signal ack        : std_logic;
begin

    -- Edge detector on cap_trig (2-FF synchronizer + edge)
    p_sync : process(clk_i)
    begin
        if rising_edge(clk_i) then
            trig_sync <= trig_sync(1 downto 0) & cap_trig_i;
        end if;
    end process;
    trig_rise <= '1' when trig_sync(2) = '1' and trig_sync(1) = '0' else '0';

    -- Free-running counter
    p_counter : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                counter <= (others => '0');
            else
                counter <= counter + 1;
            end if;
        end if;
    end process;

    -- Capture + flag
    p_capture : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                cap_flag <= '0';
                cap_en   <= '0';
                irq_en   <= '0';
                ack      <= '0';
            else
                -- capture on rising edge
                if trig_rise = '1' and cap_en = '1' then
                    capture  <= counter;
                    cap_flag <= '1';
                end if;

                -- clear cap_flag on CONTROL write
                if wb_stb_i = '1' and wb_we_i = '1' and wb_adr_i = "010" then
                    cap_en  <= wb_dat_i(0);
                    irq_en  <= wb_dat_i(1);
                    cap_flag <= '0';
                end if;

                -- single-cycle ack
                ack <= wb_stb_i and not ack;
            end if;
        end if;
    end process;

    -- IRQ output: level, active-high
    irq_o <= cap_flag and irq_en;

    -- Wishbone read mux
    process(all)
    begin
        wb_dat_o <= (others => '0');
        if wb_we_i = '0' then
            case wb_adr_i is
                when "000" =>   -- 0x00: COUNTER
                    wb_dat_o <= std_logic_vector(counter);
                when "001" =>   -- 0x04: CAPTURE
                    wb_dat_o <= std_logic_vector(capture);
                when "010" =>   -- 0x08: CONTROL
                    wb_dat_o <= (others => '0');
                    wb_dat_o(2) <= cap_flag;
                    wb_dat_o(1) <= irq_en;
                    wb_dat_o(0) <= cap_en;
                when others =>
                    null;
            end case;
        end if;
    end process;

    wb_ack_o <= ack;

end architecture rtl;
