-- wm8731_ctrl.vhd -- WM8731 I2C configuration controller
--
-- Sends 10 register writes to WM8731 on power-up via I2C.
-- Slave address: 0x34 (7-bit 0x1A << 1, write).
-- I2C clock: 50 MHz / 2500 = 20 kHz.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wm8731_ctrl is
    port (
        clk_i      : in  std_logic;
        rst_n_i    : in  std_logic;
        i2c_sclk_o : out std_logic;
        i2c_sdat   : inout std_logic;
        ready_o    : out std_logic
    );
end entity wm8731_ctrl;

architecture rtl of wm8731_ctrl is

    constant CLK_DIV : integer := 1250; -- half SCL period (~25 us)

    type reg_t is array(0 to 9) of std_logic_vector(15 downto 0);
    constant CFG : reg_t := (
        x"001A", x"001A",  -- 0,1: Line In -6dB
        x"007B", x"007B",  -- 2,3: Headphone 0dB
        x"0010",            -- 4:  DAC on, bypass off, HPOUT on
        x"0006",            -- 5: 16-bit I2S
        x"0000",            -- 6: all power on
        x"0001",            -- 7: I2S 16-bit slave
        x"0006",            -- 8: 48kHz USB mode (PLL accepts 12.5 MHz MCLK)
        x"0000"             -- 9: DAC soft-mute OFF
    );

    type state_t is (S_IDLE, S_START, S_BIT_LOW, S_BIT_HIGH, S_STOP1, S_STOP2);
    signal state    : state_t;
    signal cnt      : integer range 0 to CLK_DIV;
    signal sda_r    : std_logic;
    signal scl_r    : std_logic;
    signal ready_r  : std_logic;
    signal reg_idx  : integer range 0 to 10;
    signal bit_idx  : integer range 0 to 8;
    signal shift    : std_logic_vector(7 downto 0);
    signal phase    : integer range 0 to 2;

begin

    i2c_sclk_o <= scl_r;
    i2c_sdat   <= '0' when sda_r = '0' else 'Z';
    ready_o    <= ready_r;

    p_main : process(clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            state   <= S_IDLE;
            cnt     <= 0;
            sda_r   <= '1';
            scl_r   <= '1';
            ready_r <= '0';
            reg_idx <= 0;
            bit_idx <= 8;
            shift   <= x"34";
            phase   <= 0;

        elsif rising_edge(clk_i) then

            case state is

                when S_IDLE =>
                    if reg_idx < 10 then
                        shift   <= x"34";
                        bit_idx <= 8;
                        phase   <= 0;
                        state   <= S_START;
                    else
                        ready_r <= '1';
                    end if;

                when S_START =>
                    sda_r <= '0'; -- SDA fall while SCL high = START
                    cnt   <= 0;
                    state <= S_BIT_LOW;

                when S_BIT_LOW =>
                    cnt <= cnt + 1;
                    if cnt = CLK_DIV - 1 then
                        -- Before raising SCL, set SDA data
                        -- For ACK bit (bit_idx=0): release SDA so slave can pull low
                        if bit_idx = 0 then
                            sda_r <= '1'; -- release for ACK
                        else
                            sda_r <= shift(bit_idx - 1);
                        end if;
                        scl_r <= '1';
                        cnt   <= 0;
                        state <= S_BIT_HIGH;
                    end if;

                when S_BIT_HIGH =>
                    cnt <= cnt + 1;
                    if cnt = CLK_DIV then
                        scl_r <= '0';
                        cnt   <= 0;

                        if bit_idx = 0 then
                            -- ACK bit done, start next byte or STOP
                            if phase = 0 then
                                shift   <= CFG(reg_idx)(15 downto 8);
                                bit_idx <= 8;
                                phase   <= 1;
                            elsif phase = 1 then
                                shift   <= CFG(reg_idx)(7 downto 0);
                                bit_idx <= 8;
                                phase   <= 2;
                            elsif phase = 2 then
                                reg_idx <= reg_idx + 1;
                                sda_r   <= '0';
                                state   <= S_STOP1;
                            end if;
                            state <= S_BIT_LOW;
                        else
                            bit_idx <= bit_idx - 1;
                            state   <= S_BIT_LOW;
                        end if;
                    end if;

                when S_STOP1 =>
                    cnt <= cnt + 1;
                    if cnt = CLK_DIV - 1 then
                        scl_r <= '1';
                        cnt   <= 0;
                        state <= S_STOP2;
                    end if;

                when S_STOP2 =>
                    cnt <= cnt + 1;
                    if cnt = CLK_DIV then
                        sda_r <= '1'; -- SDA rises while SCL high = STOP
                        state <= S_IDLE;
                    end if;

            end case;
        end if;
    end process;

end architecture rtl;
