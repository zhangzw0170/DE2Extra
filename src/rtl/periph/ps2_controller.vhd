-- ps2_controller.vhd — PS/2 键盘控制器 (RX FIFO + host TX)
--
-- 功能:
--   - 已验证的设备到主机接收路径 (RX FIFO)
--   - 最小主机发送路径: CPU 可发送单字节命令到键盘
--   - 发送完成后, 第一个设备响应字节单独返回给 CPU
--
-- 寄存器映射 (偏移量, 字节地址):
--   0x00: DATA   (读 = pop RX FIFO, 返回扫描码)
--   0x04: STATUS
--         [0]    rx_ready
--         [1]    rx_overflow
--         [15:8] rx_count
--         [16]   tx_busy
--         [17]   tx_done      (sticky)
--         [18]   tx_error     (sticky)
--         [19]   tx_resp_valid(sticky)
--         [27:20]tx_resp_byte
--         [28]   bus_idle
--   0x08: CTRL   [0]=irq_enable
--   0x0C: TXDATA (写 = 发送 1 字节; 读 = tx_resp_byte)
--
-- STATUS 写 1 清 sticky:
--   bit1  -> clear rx_overflow
--   bit17 -> clear tx_done
--   bit18 -> clear tx_error
--   bit19 -> clear tx_resp_valid

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ps2_controller is
    port (
        clk_50m_i   : in  std_logic;
        rst_n_i     : in  std_logic;

        -- PS/2 物理接口
        ps2_clk_i   : in  std_logic;
        ps2_dat_i   : in  std_logic;
        ps2_clk_oe_o : out std_logic; -- '1' = pull low, '0' = release
        ps2_dat_oe_o : out std_logic; -- '1' = pull low, '0' = release

        -- 寄存器接口 (32-bit 字地址)
        reg_adr_i   : in  std_logic_vector(3 downto 0);
        reg_dat_i   : in  std_logic_vector(31 downto 0);
        reg_dat_o   : out std_logic_vector(31 downto 0);
        reg_we_i    : in  std_logic;
        reg_stb_i   : in  std_logic;
        reg_ack_o   : out std_logic;

        -- 调试/状态
        ps2_valid_o : out std_logic;
        ps2_scancode_o : out std_logic_vector(7 downto 0);

        -- 中断
        irq_o       : out std_logic
    );
end ps2_controller;

architecture rtl of ps2_controller is

    constant FIFO_DEPTH_C        : integer := 16;
    constant IDLE_MIN_TICKS_C    : integer := 2500;     -- 50us @ 50MHz
    constant CLK_HOLD_TICKS_C    : integer := 6000;     -- 120us @ 50MHz
    constant DATA_SETUP_TICKS_C  : integer := 250;      -- 5us @ 50MHz
    constant TX_TIMEOUT_TICKS_C  : integer := 2_500_000; -- 50ms @ 50MHz
    type fifo_array_t is array (0 to FIFO_DEPTH_C - 1) of std_logic_vector(7 downto 0);
    type tx_state_t is (TX_IDLE, TX_WAIT_IDLE, TX_PULL_CLK, TX_PULL_DAT, TX_SEND, TX_WAIT_RESP);

    function odd_parity_bit(data_i : std_logic_vector(7 downto 0)) return std_logic is
        variable parity_v : std_logic := '0';
    begin
        for i in data_i'range loop
            parity_v := parity_v xor data_i(i);
        end loop;
        return not parity_v;
    end function;

    function tx_frame_bit(data_i : std_logic_vector(7 downto 0); bit_idx_i : integer) return std_logic is
    begin
        case bit_idx_i is
            when 0  => return '0'; -- start
            when 1  => return data_i(0);
            when 2  => return data_i(1);
            when 3  => return data_i(2);
            when 4  => return data_i(3);
            when 5  => return data_i(4);
            when 6  => return data_i(5);
            when 7  => return data_i(6);
            when 8  => return data_i(7);
            when 9  => return odd_parity_bit(data_i);
            when others => return '1'; -- stop
        end case;
    end function;

    signal rx_scan_code   : std_logic_vector(7 downto 0);
    signal rx_valid       : std_logic;
    signal rx_enable      : std_logic;
    signal sync_clk_level : std_logic;
    signal sync_clk_fall  : std_logic;
    signal sync_dat       : std_logic;

    signal fifo_mem       : fifo_array_t := (others => (others => '0'));
    signal fifo_wr_ptr    : integer range 0 to FIFO_DEPTH_C - 1 := 0;
    signal fifo_rd_ptr    : integer range 0 to FIFO_DEPTH_C - 1 := 0;
    signal fifo_count     : integer range 0 to FIFO_DEPTH_C := 0;
    signal fifo_full      : std_logic;
    signal fifo_empty     : std_logic;

    signal ctrl_irq_en    : std_logic := '0';
    signal overflow_flag  : std_logic := '0';

    signal tx_state       : tx_state_t := TX_IDLE;
    signal tx_data_byte   : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_bit_idx     : integer range 0 to 10 := 0;
    signal tx_timer       : integer range 0 to TX_TIMEOUT_TICKS_C := 0;
    signal idle_timer     : integer range 0 to IDLE_MIN_TICKS_C := 0;
    signal tx_done_flag   : std_logic := '0';
    signal tx_error_flag  : std_logic := '0';
    signal tx_resp_valid_flag : std_logic := '0';
    signal tx_resp_byte   : std_logic_vector(7 downto 0) := (others => '0');
    signal ps2_clk_oe     : std_logic := '0';
    signal ps2_dat_oe     : std_logic := '0';
    signal reg_ack        : std_logic := '0';
    signal reg_rdata      : std_logic_vector(31 downto 0) := (others => '0');

begin

    u_sync : entity work.ps2_sync
    port map (
        clk      => clk_50m_i,
        ps2_clk  => ps2_clk_i,
        ps2_dat  => ps2_dat_i,
        clk_sync => sync_clk_level,
        clk_fall => sync_clk_fall,
        dat_sync => sync_dat
    );

    rx_enable <= '1' when (tx_state = TX_IDLE) or
                           (tx_state = TX_WAIT_IDLE) or
                           (tx_state = TX_WAIT_RESP) else '0';

    u_rx : entity work.ps2_receiver
    port map (
        clk       => clk_50m_i,
        enable_i  => rx_enable,
        clk_fall  => sync_clk_fall,
        dat_sync  => sync_dat,
        scan_code => rx_scan_code,
        valid     => rx_valid
    );

    fifo_full  <= '1' when fifo_count = FIFO_DEPTH_C else '0';
    fifo_empty <= '1' when fifo_count = 0 else '0';

    process(clk_50m_i, rst_n_i)
        variable do_pop_v : boolean;
    begin
        if rst_n_i = '0' then
            fifo_wr_ptr        <= 0;
            fifo_rd_ptr        <= 0;
            fifo_count         <= 0;
            overflow_flag      <= '0';
            ctrl_irq_en        <= '0';
            tx_state           <= TX_IDLE;
            tx_data_byte       <= (others => '0');
            tx_bit_idx         <= 0;
            tx_timer           <= 0;
            idle_timer         <= 0;
            tx_done_flag       <= '0';
            tx_error_flag      <= '0';
            tx_resp_valid_flag <= '0';
            tx_resp_byte       <= (others => '0');
            ps2_clk_oe         <= '0';
            ps2_dat_oe         <= '0';
            reg_ack            <= '0';
            reg_rdata          <= (others => '0');
            for i in 0 to FIFO_DEPTH_C - 1 loop
                fifo_mem(i) <= (others => '0');
            end loop;
        elsif rising_edge(clk_50m_i) then
            reg_ack <= '0';
            do_pop_v := false;

            ps2_clk_oe <= '0';
            ps2_dat_oe <= '0';

            case tx_state is
                when TX_IDLE =>
                    tx_timer   <= 0;
                    idle_timer <= 0;

                when TX_WAIT_IDLE =>
                    if sync_clk_level = '1' and sync_dat = '1' then
                        if idle_timer = IDLE_MIN_TICKS_C then
                            tx_state   <= TX_PULL_CLK;
                            tx_timer   <= 0;
                            idle_timer <= 0;
                        else
                            idle_timer <= idle_timer + 1;
                        end if;
                    else
                        idle_timer <= 0;
                    end if;

                    if tx_timer = TX_TIMEOUT_TICKS_C then
                        tx_state      <= TX_IDLE;
                        tx_done_flag  <= '1';
                        tx_error_flag <= '1';
                    else
                        tx_timer <= tx_timer + 1;
                    end if;

                when TX_PULL_CLK =>
                    ps2_clk_oe <= '1';

                    if tx_timer = CLK_HOLD_TICKS_C then
                        tx_state <= TX_PULL_DAT;
                        tx_timer <= 0;
                    else
                        tx_timer <= tx_timer + 1;
                    end if;

                when TX_PULL_DAT =>
                    ps2_clk_oe <= '1';
                    ps2_dat_oe <= '1';

                    if tx_timer = DATA_SETUP_TICKS_C then
                        tx_state   <= TX_SEND;
                        tx_timer   <= 0;
                        tx_bit_idx <= 0;
                    else
                        tx_timer <= tx_timer + 1;
                    end if;

                when TX_SEND =>
                    if tx_frame_bit(tx_data_byte, tx_bit_idx) = '0' then
                        ps2_dat_oe <= '1';
                    end if;

                    if sync_clk_fall = '1' then
                        if tx_bit_idx = 10 then
                            tx_state <= TX_WAIT_RESP;
                            tx_timer <= 0;
                        else
                            tx_bit_idx <= tx_bit_idx + 1;
                            tx_timer   <= 0;
                        end if;
                    elsif tx_timer = TX_TIMEOUT_TICKS_C then
                        tx_state      <= TX_IDLE;
                        tx_done_flag  <= '1';
                        tx_error_flag <= '1';
                    else
                        tx_timer <= tx_timer + 1;
                    end if;

                when TX_WAIT_RESP =>
                    if rx_valid = '1' then
                        tx_resp_byte       <= rx_scan_code;
                        tx_resp_valid_flag <= '1';
                        tx_done_flag       <= '1';
                        tx_error_flag      <= '0';
                        tx_state           <= TX_IDLE;
                        tx_timer           <= 0;
                    elsif tx_timer = TX_TIMEOUT_TICKS_C then
                        tx_state      <= TX_IDLE;
                        tx_done_flag  <= '1';
                        tx_error_flag <= '1';
                    else
                        tx_timer <= tx_timer + 1;
                    end if;
            end case;

            if rx_valid = '1' and tx_state /= TX_WAIT_RESP then
                if fifo_full = '0' then
                    fifo_mem(fifo_wr_ptr) <= rx_scan_code;
                    if fifo_wr_ptr = FIFO_DEPTH_C - 1 then
                        fifo_wr_ptr <= 0;
                    else
                        fifo_wr_ptr <= fifo_wr_ptr + 1;
                    end if;
                    fifo_count <= fifo_count + 1;
                else
                    overflow_flag <= '1';
                end if;
            end if;

            if reg_stb_i = '1' then
                reg_ack <= '1';

                if reg_we_i = '1' then
                    case reg_adr_i is
                        when x"4" =>
                            if reg_dat_i(1) = '1' then
                                overflow_flag <= '0';
                            end if;
                            if reg_dat_i(17) = '1' then
                                tx_done_flag <= '0';
                            end if;
                            if reg_dat_i(18) = '1' then
                                tx_error_flag <= '0';
                            end if;
                            if reg_dat_i(19) = '1' then
                                tx_resp_valid_flag <= '0';
                            end if;
                        when x"8" =>
                            ctrl_irq_en <= reg_dat_i(0);
                        when x"C" =>
                            if tx_state = TX_IDLE then
                                tx_data_byte       <= reg_dat_i(7 downto 0);
                                tx_resp_valid_flag <= '0';
                                tx_done_flag       <= '0';
                                tx_error_flag      <= '0';
                                tx_state           <= TX_WAIT_IDLE;
                                tx_timer           <= 0;
                                idle_timer         <= 0;
                            else
                                tx_done_flag  <= '1';
                                tx_error_flag <= '1';
                            end if;
                        when others =>
                            null;
                    end case;
                else
                    case reg_adr_i is
                        when x"0" =>
                            if fifo_empty = '0' then
                                reg_rdata <= x"000000" & fifo_mem(fifo_rd_ptr);
                                do_pop_v := true;
                            else
                                reg_rdata <= (others => '0');
                            end if;
                        when x"4" =>
                            reg_rdata <= (others => '0');
                            reg_rdata(0) <= not fifo_empty;
                            reg_rdata(1) <= overflow_flag;
                            reg_rdata(15 downto 8) <= std_logic_vector(to_unsigned(fifo_count, 8));
                            if tx_state /= TX_IDLE then
                                reg_rdata(16) <= '1';
                            end if;
                            reg_rdata(17) <= tx_done_flag;
                            reg_rdata(18) <= tx_error_flag;
                            reg_rdata(19) <= tx_resp_valid_flag;
                            reg_rdata(27 downto 20) <= tx_resp_byte;
                            if sync_clk_level = '1' and sync_dat = '1' then
                                reg_rdata(28) <= '1';
                            end if;
                        when x"8" =>
                            reg_rdata <= (others => '0');
                            reg_rdata(0) <= ctrl_irq_en;
                        when x"C" =>
                            reg_rdata <= (others => '0');
                            reg_rdata(7 downto 0) <= tx_resp_byte;
                        when others =>
                            reg_rdata <= (others => '0');
                    end case;
                end if;
            end if;

            if do_pop_v then
                if fifo_rd_ptr = FIFO_DEPTH_C - 1 then
                    fifo_rd_ptr <= 0;
                else
                    fifo_rd_ptr <= fifo_rd_ptr + 1;
                end if;
                fifo_count <= fifo_count - 1;
            end if;
        end if;
    end process;

    reg_ack_o       <= reg_ack;
    reg_dat_o       <= reg_rdata;
    ps2_clk_oe_o    <= ps2_clk_oe;
    ps2_dat_oe_o    <= ps2_dat_oe;
    ps2_valid_o     <= rx_valid;
    ps2_scancode_o  <= rx_scan_code;
    irq_o <= '1' when ctrl_irq_en = '1' and fifo_empty = '0' else '0';

end rtl;
