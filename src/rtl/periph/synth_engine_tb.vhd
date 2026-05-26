-- synth_engine_tb.vhd -- Testbench for synth_engine
--
-- Tests:
--  1. I2C initialization sequence
--  2. Wishbone register read/write
--  3. DDS output with hardcoded tuning word (A4 = 440 Hz)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity synth_engine_tb is
end entity synth_engine_tb;

architecture sim of synth_engine_tb is

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

    signal clk     : std_logic := '0';
    signal rst_n   : std_logic := '0';

    -- Wishbone
    signal wb_adr  : std_logic_vector(4 downto 0);
    signal wb_dat_i : std_logic_vector(31 downto 0);
    signal wb_dat_o : std_logic_vector(31 downto 0);
    signal wb_we   : std_logic;
    signal wb_stb  : std_logic;
    signal wb_ack  : std_logic;

    -- Audio
    signal aud_xck    : std_logic;
    signal aud_bclk   : std_logic;
    signal aud_daclrck : std_logic;
    signal aud_dacdat  : std_logic;
    signal i2c_sclk   : std_logic;
    signal i2c_sdat   : std_logic;

    -- Simulated WM8731 BCLK/LRCK
    constant BCLK_PERIOD : time := 325 ns; -- ~3.072 MHz
    constant LRCK_PERIOD : time := 20.83 us; -- 48 kHz
    signal bclk_gen    : std_logic := '0';
    signal lrck_gen    : std_logic := '0';

begin

    -- Clock
    clk <= not clk after CLK_PERIOD / 2;

    -- Reset
    p_rst : process
    begin
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait;
    end process;

    -- Simulate WM8731 BCLK and LRCK in slave mode
    p_bclk : process
    begin
        bclk_gen <= not bclk_gen after BCLK_PERIOD / 2;
    end process;

    p_lrck : process
    begin
        lrck_gen <= not lrck_gen after LRCK_PERIOD / 2;
    end process;

    -- DUT
    u_dut : entity work.synth_engine
        port map (
            clk_i        => clk,
            rst_n_i      => rst_n,
            wb_adr_i     => wb_adr,
            wb_dat_i     => wb_dat_i,
            wb_dat_o     => wb_dat_o,
            wb_we_i      => wb_we,
            wb_stb_i     => wb_stb,
            wb_ack_o     => wb_ack,
            aud_xck_o    => aud_xck,
            aud_bclk_i   => bclk_gen,
            aud_daclrck_i=> lrck_gen,
            aud_dacdat_o => aud_dacdat,
            i2c_sclk_o   => i2c_sclk,
            i2c_sdat_o   => i2c_sdat
        );

    -- Stimulus
    p_stim : process
        variable tw_a4 : std_logic_vector(31 downto 0);
    begin
        wait until rst_n = '1';
        wait for 1 us;

        -- Wait for codec ready (I2C init takes ~5ms simulated, but we'll wait a bit)
        -- In simulation, just wait for enough I2C cycles
        report "--- Test 1: Wait for codec ready ---";
        wait until i2c_sclk'event and i2c_sclk = '0';
        wait for 10 us; -- let I2C run

        report "--- Test 2: Write Track1 tuning word (A4 = 440 Hz) ---";
        -- TW = 440 * 2^32 / 48000 = 39,276,827 = 0x0257_EEDB
        tw_a4 := x"0257EEDB";

        -- Write NOTE register (TW stored in full 32 bits)
        wb_adr  <= "00010"; -- T1 NOTE
        wb_dat_i <= tw_a4;
        wb_we   <= '1';
        wb_stb  <= '1';
        wait until wb_ack = '1';
        wait until rising_edge(clk);
        wb_stb  <= '0';
        wb_we   <= '0';
        wait for 100 ns;

        -- Set OSC1 volume to max, sine wave, no octave shift
        wb_adr  <= "00011"; -- T1 OSC1
        wb_dat_i <= x"0000FF00"; -- wave=00(sin), octave=00, vol=255
        wb_we   <= '1';
        wb_stb  <= '1';
        wait until wb_ack = '1';
        wait until rising_edge(clk);
        wb_stb  <= '0';
        wb_we   <= '0';
        wait for 100 ns;

        -- Write Track2 tuning word (C4 = 261.63 Hz)
        -- TW = 261.63 * 2^32 / 48000 = 23,322,397 = 0x0163E7DD
        wb_adr  <= "01000"; -- T2 NOTE
        wb_dat_i <= x"0163E7DD";
        wb_we   <= '1';
        wb_stb  <= '1';
        wait until wb_ack = '1';
        wait until rising_edge(clk);
        wb_stb  <= '0';
        wb_we   <= '0';
        wait for 100 ns;

        -- Set T2 OSC1 volume to max
        wb_adr  <= "01001"; -- T2 OSC1
        wb_dat_i <= x"0000FF00";
        wb_we   <= '1';
        wb_stb  <= '1';
        wait until wb_ack = '1';
        wait until rising_edge(clk);
        wb_stb  <= '0';
        wb_we   <= '0';
        wait for 100 ns;

        report "--- Test 3: Read status register ---";
        wb_adr  <= "00001"; -- STATUS
        wb_dat_i <= (others => '0');
        wb_we   <= '0';
        wb_stb  <= '1';
        wait until wb_ack = '1';
        wait until rising_edge(clk);
        wb_stb  <= '0';
        report "Status register: " & integer'image(to_integer(unsigned(wb_dat_o)));
        wait for 100 ns;

        report "--- Test 4: Monitor I2S output for a few sample periods ---";
        wait for 200 us; -- ~10 audio samples

        report "--- Simulation done ---";
        wait;
    end process;

end architecture sim;
