-- 实验9：串行通信芯片（UART）
-- 波特率9600，16x过采样
-- HEX5-HEX4, LEDR[15:8] 显示接收数据；HEX1-HEX0, LEDG[7:0] 显示待发送数据(SW)
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity uart_top is
    port (
        CLOCK_50   : in  std_logic;
        SW         : in  std_logic_vector(7 downto 0);
        KEY0_N     : in  std_logic;
        UART_TXD   : out std_logic;
        UART_RXD   : in  std_logic;
        LEDR       : out std_logic_vector(15 downto 0);
        LEDG       : out std_logic_vector(7 downto 0);
        HEX5       : out std_logic_vector(6 downto 0);
        HEX4       : out std_logic_vector(6 downto 0);
        HEX1       : out std_logic_vector(6 downto 0);
        HEX0       : out std_logic_vector(6 downto 0)
    );
end uart_top;

architecture behavioral of uart_top is
    constant CLK_PER_SAMPLE   : integer := 326;
    constant SAMPLES_PER_BIT  : integer := 16;
    constant HALF_BIT_SAMPLES : integer := 8;

    signal sample_timer : integer range 0 to CLK_PER_SAMPLE - 1 := 0;
    signal sample_tick  : std_logic := '0';

    signal tx_cnt : integer range 0 to 15 := 0;
    signal rx_cnt : integer range 0 to 15 := 0;

    type tx_state_t is (TX_IDLE, TX_START, TX_DATA, TX_STOP);
    signal tx_state    : tx_state_t := TX_IDLE;
    signal tx_bit_cnt  : integer range 0 to 7 := 0;
    signal tx_data_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_send     : std_logic := '0';
    signal key0_prev   : std_logic := '1';

    type rx_state_t is (RX_IDLE, RX_START_CHECK, RX_DATA, RX_STOP);
    signal rx_state      : rx_state_t := RX_IDLE;
    signal rx_bit_cnt    : integer range 0 to 7 := 0;
    signal rx_shift      : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_data_out   : std_logic_vector(7 downto 0) := (others => '0');
    signal rxd_sync      : std_logic_vector(2 downto 0) := "111";
    signal rx_data_valid : std_logic := '0';

    -- 七段译码函数（共阳极）
    function hex7seg(nib : std_logic_vector(3 downto 0))
        return std_logic_vector is
    begin
        case nib is
            when "0000" => return "1000000";
            when "0001" => return "1111001";
            when "0010" => return "0100100";
            when "0011" => return "0110000";
            when "0100" => return "0011001";
            when "0101" => return "0010010";
            when "0110" => return "0000010";
            when "0111" => return "1111000";
            when "1000" => return "0000000";
            when "1001" => return "0010000";
            when "1010" => return "0001000";
            when "1011" => return "0000011";
            when "1100" => return "1000110";
            when "1101" => return "0100001";
            when "1110" => return "0000110";
            when others => return "0001110";
        end case;
    end function;
begin

    -- 采样定时器
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            if sample_timer = CLK_PER_SAMPLE - 1 then
                sample_timer <= 0;
                sample_tick <= '1';
            else
                sample_timer <= sample_timer + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;

    -- RXD二级同步器
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            rxd_sync <= rxd_sync(1 downto 0) & UART_RXD;
        end if;
    end process;

    -- KEY0 上升沿检测
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            key0_prev <= KEY0_N;
        end if;
    end process;

    tx_send <= '1' when key0_prev = '0' and KEY0_N = '1' else '0';

    -- ===== UART 发送 =====
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            -- 空闲时持续拉高，确保上电后TXD立即为'1'
            if tx_state = TX_IDLE then
                UART_TXD <= '1';
            end if;

            if sample_tick = '1' then
                if tx_cnt = SAMPLES_PER_BIT - 1 then
                    tx_cnt <= 0;
                else
                    tx_cnt <= tx_cnt + 1;
                end if;

                case tx_state is
                    when TX_IDLE =>
                        UART_TXD <= '1';
                    when TX_START =>
                        if tx_cnt = 0 then
                            UART_TXD <= '0';
                        elsif tx_cnt = SAMPLES_PER_BIT - 1 then
                            tx_state <= TX_DATA;
                        end if;
                    when TX_DATA =>
                        if tx_cnt = 0 then
                            UART_TXD <= tx_data_reg(0);
                            tx_data_reg <= '0' & tx_data_reg(7 downto 1);
                            if tx_bit_cnt = 7 then
                                tx_state <= TX_STOP;
                            else
                                tx_bit_cnt <= tx_bit_cnt + 1;
                            end if;
                        end if;
                    when TX_STOP =>
                        if tx_cnt = 0 then
                            UART_TXD <= '1';
                        elsif tx_cnt = SAMPLES_PER_BIT - 1 then
                            tx_state <= TX_IDLE;
                        end if;
                end case;
            end if;

            if tx_send = '1' and tx_state = TX_IDLE then
                tx_data_reg <= SW;
                tx_state <= TX_START;
                tx_bit_cnt <= 0;
                tx_cnt <= 0;
            end if;
        end if;
    end process;

    -- ===== UART 接收（16x过采样）=====
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            rx_data_valid <= '0';
            if sample_tick = '1' then
                case rx_state is
                    when RX_IDLE =>
                        if rxd_sync(1) = '0' then
                            rx_state <= RX_START_CHECK;
                            rx_cnt <= 0;
                        end if;
                    when RX_START_CHECK =>
                        if rx_cnt = HALF_BIT_SAMPLES - 1 then
                            if rxd_sync(1) = '0' then
                                rx_state <= RX_DATA;
                                rx_bit_cnt <= 0;
                            else
                                rx_state <= RX_IDLE;
                            end if;
                        end if;
                    when RX_DATA =>
                        if rx_cnt = HALF_BIT_SAMPLES - 1 then
                            rx_shift <= rxd_sync(1) & rx_shift(7 downto 1);
                            if rx_bit_cnt = 7 then
                                rx_state <= RX_STOP;
                            else
                                rx_bit_cnt <= rx_bit_cnt + 1;
                            end if;
                        end if;
                    when RX_STOP =>
                        if rx_cnt = HALF_BIT_SAMPLES - 1 then
                            if rxd_sync(1) = '1' then
                                rx_data_out <= rx_shift;
                                rx_data_valid <= '1';
                            end if;
                            rx_state <= RX_IDLE;
                        end if;
                end case;

                if rx_state /= RX_IDLE then
                    if rx_cnt = SAMPLES_PER_BIT - 1 then
                        rx_cnt <= 0;
                    else
                        rx_cnt <= rx_cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ===== 输出显示 =====
    -- 接收数据 → LEDR[15:8] + LEDR[7:0]
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            if rx_data_valid = '1' then
                LEDR(7 downto 0) <= rx_data_out;
            end if;
        end if;
    end process;
    LEDR(15 downto 8) <= rx_data_out;

    -- 待发送数据 → LEDG
    LEDG <= SW;

    -- 接收数据 → HEX5(高4位), HEX4(低4位)
    HEX5 <= hex7seg(rx_data_out(7 downto 4));
    HEX4 <= hex7seg(rx_data_out(3 downto 0));

    -- 待发送数据 → HEX1(高4位), HEX0(低4位)
    HEX1 <= hex7seg(SW(7 downto 4));
    HEX0 <= hex7seg(SW(3 downto 0));

end behavioral;
