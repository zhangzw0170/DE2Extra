-- uart_jtag_bridge.vhd — UART <-> JTAG UART 桥
--
-- 把 NEORV32 UART TX 镜像到 JTAG UART，便于在 PC 端抓日志；
-- 同时把 PC 端写入 JTAG UART 的字节重新串行化，注入到 NEORV32 UART RX。
--
-- 时钟: 50MHz, UART 波特率由 generic 配置 (默认 115200)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_jtag_bridge is
    generic (
        CLOCK_FREQ_HZ : natural := 50_000_000;
        BAUD_RATE     : natural := 115200
    );
    port (
        clk_i   : in  std_logic;
        rst_n_i : in  std_logic;

        -- NEORV32 UART TX 输入
        uart_tx_i : in  std_logic;
        uart_rx_o : out std_logic;

        -- JTAG UART Avalon-MM 主机接口
        av_chipselect  : out std_logic;
        av_address     : out std_logic;
        av_read_n      : out std_logic;
        av_readdata    : in  std_logic_vector(31 downto 0);
        av_write_n     : out std_logic;
        av_writedata   : out std_logic_vector(31 downto 0);
        av_waitrequest : in  std_logic
    );
end entity uart_jtag_bridge;

architecture rtl of uart_jtag_bridge is

    constant BITS_PER_SYMBOL_C : natural := CLOCK_FREQ_HZ / BAUD_RATE;
    constant HALF_BIT_C        : natural := BITS_PER_SYMBOL_C / 2;
    constant POLL_DIV_C        : natural := CLOCK_FREQ_HZ / 200000;

    type tx_state_t is (
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_STOP
    );

    type rx_state_t is (
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP
    );

    type av_state_t is (
        AV_IDLE,
        AV_WRITE_TX,
        AV_READ_RX
    );

    signal tx_state         : tx_state_t := TX_IDLE;
    signal tx_bit_cnt       : unsigned(2 downto 0) := (others => '0');
    signal tx_bit_timer     : unsigned(15 downto 0) := (others => '0');
    signal tx_shift_reg     : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_prev          : std_logic := '1';
    signal tx_byte_pending  : std_logic := '0';
    signal tx_byte_data     : std_logic_vector(7 downto 0) := (others => '0');

    signal rx_state         : rx_state_t := RX_IDLE;
    signal rx_bit_cnt       : unsigned(2 downto 0) := (others => '0');
    signal rx_bit_timer     : unsigned(15 downto 0) := (others => '0');
    signal rx_shift_reg     : std_logic_vector(7 downto 0) := (others => '1');
    signal rx_line          : std_logic := '1';

    signal av_state         : av_state_t := AV_IDLE;
    signal poll_div         : unsigned(15 downto 0) := (others => '0');

begin

    uart_rx_o <= rx_line;
    av_address <= '0';

    p_bridge : process (clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            tx_state         <= TX_IDLE;
            tx_bit_cnt       <= (others => '0');
            tx_bit_timer     <= (others => '0');
            tx_shift_reg     <= (others => '0');
            tx_prev          <= '1';
            tx_byte_pending  <= '0';
            tx_byte_data     <= (others => '0');
            rx_state         <= RX_IDLE;
            rx_bit_cnt       <= (others => '0');
            rx_bit_timer     <= (others => '0');
            rx_shift_reg     <= (others => '1');
            rx_line          <= '1';
            av_state         <= AV_IDLE;
            poll_div         <= (others => '0');
            av_chipselect <= '0';
            av_read_n    <= '1';
            av_write_n   <= '1';
            av_writedata <= (others => '0');
        elsif rising_edge(clk_i) then
            tx_prev <= uart_tx_i;

            -- 默认: Avalon 空闲
            av_chipselect <= '0';
            av_read_n    <= '1';
            av_write_n   <= '1';

            case tx_state is
                when TX_IDLE =>
                    if tx_prev = '1' and uart_tx_i = '0' then
                        tx_bit_timer <= to_unsigned(HALF_BIT_C, tx_bit_timer'length);
                        tx_state     <= TX_START;
                    end if;

                when TX_START =>
                    if tx_bit_timer = 0 then
                        if uart_tx_i = '0' then
                            tx_bit_timer <= to_unsigned(BITS_PER_SYMBOL_C - 1, tx_bit_timer'length);
                            tx_bit_cnt   <= (others => '0');
                            tx_state     <= TX_DATA;
                        else
                            tx_state <= TX_IDLE;
                        end if;
                    else
                        tx_bit_timer <= tx_bit_timer - 1;
                    end if;

                when TX_DATA =>
                    if tx_bit_timer = 0 then
                        tx_shift_reg <= uart_tx_i & tx_shift_reg(7 downto 1);
                        if tx_bit_cnt = 7 then
                            tx_bit_timer <= to_unsigned(BITS_PER_SYMBOL_C - 1, tx_bit_timer'length);
                            tx_state     <= TX_STOP;
                        else
                            tx_bit_cnt   <= tx_bit_cnt + 1;
                            tx_bit_timer <= to_unsigned(BITS_PER_SYMBOL_C - 1, tx_bit_timer'length);
                        end if;
                    else
                        tx_bit_timer <= tx_bit_timer - 1;
                    end if;

                when TX_STOP =>
                    if tx_bit_timer = 0 then
                        if tx_byte_pending = '0' then
                            tx_byte_pending <= '1';
                            tx_byte_data    <= tx_shift_reg;
                        end if;
                        tx_state <= TX_IDLE;
                    else
                        tx_bit_timer <= tx_bit_timer - 1;
                    end if;
            end case;

            case rx_state is
                when RX_IDLE =>
                    rx_line <= '1';

                when RX_START =>
                    rx_line <= '0';
                    if rx_bit_timer = 0 then
                        rx_line      <= rx_shift_reg(0);
                        rx_bit_timer <= to_unsigned(BITS_PER_SYMBOL_C - 1, rx_bit_timer'length);
                        rx_bit_cnt   <= (others => '0');
                        rx_state     <= RX_DATA;
                    else
                        rx_bit_timer <= rx_bit_timer - 1;
                    end if;

                when RX_DATA =>
                    if rx_bit_timer = 0 then
                        if rx_bit_cnt = 7 then
                            rx_line      <= '1';
                            rx_bit_timer <= to_unsigned(BITS_PER_SYMBOL_C - 1, rx_bit_timer'length);
                            rx_state     <= RX_STOP;
                        else
                            rx_shift_reg <= '1' & rx_shift_reg(7 downto 1);
                            rx_bit_cnt   <= rx_bit_cnt + 1;
                            rx_line      <= rx_shift_reg(1);
                            rx_bit_timer <= to_unsigned(BITS_PER_SYMBOL_C - 1, rx_bit_timer'length);
                        end if;
                    else
                        rx_bit_timer <= rx_bit_timer - 1;
                    end if;

                when RX_STOP =>
                    rx_line <= '1';
                    if rx_bit_timer = 0 then
                        rx_state <= RX_IDLE;
                    else
                        rx_bit_timer <= rx_bit_timer - 1;
                    end if;
            end case;

            case av_state is
                when AV_IDLE =>
                    if tx_byte_pending = '1' then
                        av_state <= AV_WRITE_TX;
                    elsif rx_state = RX_IDLE then
                        if poll_div = 0 then
                            av_state <= AV_READ_RX;
                            poll_div <= to_unsigned(POLL_DIV_C - 1, poll_div'length);
                        else
                            poll_div <= poll_div - 1;
                        end if;
                    end if;

                when AV_WRITE_TX =>
                    av_chipselect <= '1';
                    av_write_n    <= '0';
                    av_writedata  <= x"000000" & tx_byte_data;
                    if av_waitrequest = '0' then
                        tx_byte_pending <= '0';
                        av_state        <= AV_IDLE;
                    end if;

                when AV_READ_RX =>
                    av_chipselect <= '1';
                    av_read_n     <= '0';
                    if av_waitrequest = '0' then
                        if av_readdata(15) = '1' and rx_state = RX_IDLE then
                            rx_shift_reg <= av_readdata(7 downto 0);
                            rx_line      <= '0';
                            rx_bit_timer <= to_unsigned(BITS_PER_SYMBOL_C - 1, rx_bit_timer'length);
                            rx_state     <= RX_START;
                        end if;
                        av_state <= AV_IDLE;
                    end if;
            end case;
        end if;
    end process;

end architecture rtl;
