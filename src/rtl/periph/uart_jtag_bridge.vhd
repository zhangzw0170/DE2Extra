-- uart_jtag_bridge.vhd — UART TX → JTAG UART 桥
--
-- 采样 NEORV32 UART TX 串口输出，每收到一个完整字节就写入
-- Altera JTAG UART IP，无需修改固件即可在 nios2-terminal 查看输出。
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

    -- 每位时钟周期数: 50MHz / 115200 ≈ 434
    constant BITS_PER_SYMBOL : natural := CLOCK_FREQ_HZ / BAUD_RATE;
    constant HALF_BIT        : natural := BITS_PER_SYMBOL / 2;

    type state_t is (
        S_IDLE,       -- 等待 start bit (TX 下降沿)
        S_START,      -- 等半个位周期再采样 start bit
        S_DATA,       -- 采样 8 个数据位
        S_PUSH,       -- 写入 JTAG UART
        S_PUSH_WAIT   -- 等待 waitrequest 撤销
    );

    signal state      : state_t;
    signal bit_cnt    : unsigned(2 downto 0);
    signal bit_timer  : unsigned(15 downto 0);
    signal shift_reg  : std_logic_vector(7 downto 0);
    signal tx_prev    : std_logic;

begin

    p_bridge : process (clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            state        <= S_IDLE;
            bit_cnt      <= (others => '0');
            bit_timer    <= (others => '0');
            shift_reg    <= (others => '0');
            tx_prev      <= '1';
            av_chipselect <= '0';
            av_write_n   <= '1';
            av_address   <= '0';
            av_writedata <= (others => '0');
        elsif rising_edge(clk_i) then
            tx_prev <= uart_tx_i;

            -- 默认: Avalon 空闲
            av_chipselect <= '0';
            av_write_n   <= '1';

            case state is

                when S_IDLE =>
                    -- 检测 TX 下降沿 = start bit 开始
                    if tx_prev = '1' and uart_tx_i = '0' then
                        bit_timer <= to_unsigned(HALF_BIT, 16);
                        state     <= S_START;
                    end if;

                when S_START =>
                    if bit_timer = 0 then
                        -- 中点采样，确认 start bit 仍为 0
                        if uart_tx_i = '0' then
                            bit_timer <= to_unsigned(BITS_PER_SYMBOL, 16);
                            bit_cnt   <= (others => '0');
                            state     <= S_DATA;
                        else
                            state <= S_IDLE;
                        end if;
                    else
                        bit_timer <= bit_timer - 1;
                    end if;

                when S_DATA =>
                    if bit_timer = 0 then
                        -- 在每位中点采样
                        shift_reg <= uart_tx_i & shift_reg(7 downto 1);
                        if bit_cnt = 7 then
                            state <= S_PUSH;
                        else
                            bit_cnt   <= bit_cnt + 1;
                            bit_timer <= to_unsigned(BITS_PER_SYMBOL, 16);
                        end if;
                    else
                        bit_timer <= bit_timer - 1;
                    end if;

                when S_PUSH =>
                    av_chipselect <= '1';
                    av_address    <= '0';       -- data register
                    av_write_n   <= '0';
                    av_writedata <= x"000000" & shift_reg;
                    if av_waitrequest = '0' then
                        state <= S_IDLE;
                    else
                        state <= S_PUSH_WAIT;
                    end if;

                when S_PUSH_WAIT =>
                    av_chipselect <= '1';
                    av_write_n   <= '0';
                    av_writedata <= x"000000" & shift_reg;
                    if av_waitrequest = '0' then
                        state <= S_IDLE;
                    end if;

            end case;
        end if;
    end process;

    av_read_n <= '1';

end architecture rtl;
