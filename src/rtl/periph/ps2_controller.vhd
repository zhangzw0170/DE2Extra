-- ps2_controller.vhd — PS/2 键盘控制器 (RX FIFO only)
--
-- 功能:
--   - 包装已验证的 ps2_sync + ps2_receiver
--   - 16-entry × 8-bit RX FIFO 缓冲扫描码
--   - 寄存器接口
--   - IRQ 输出 (RX data_ready)
--
-- 寄存器映射 (偏移量, 字节地址):
--   0x00: DATA   (读 = pop RX FIFO, 返回字节)
--   0x04: STATUS [0]=data_ready, [1]=overflow, [15:8]=fifo_count
--   0x08: CTRL   [0]=irq_enable

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

    constant FIFO_DEPTH  : integer := 16;
    type fifo_array_t is array (0 to FIFO_DEPTH - 1) of std_logic_vector(7 downto 0);

    signal rx_scan_code  : std_logic_vector(7 downto 0);
    signal rx_valid      : std_logic;
    signal sync_clk_fall : std_logic;
    signal sync_dat      : std_logic;

    signal fifo_mem      : fifo_array_t := (others => (others => '0'));
    signal fifo_wr_ptr   : integer range 0 to FIFO_DEPTH - 1 := 0;
    signal fifo_rd_ptr   : integer range 0 to FIFO_DEPTH - 1 := 0;
    signal fifo_count    : integer range 0 to FIFO_DEPTH := 0;
    signal fifo_full     : std_logic;
    signal fifo_empty    : std_logic;

    signal ctrl_irq_en   : std_logic := '0';
    signal overflow_flag : std_logic := '0';

    signal reg_ack       : std_logic := '0';
    signal reg_rdata     : std_logic_vector(31 downto 0) := (others => '0');

begin

    u_sync : entity work.ps2_sync
    port map (
        clk      => clk_50m_i,
        ps2_clk  => ps2_clk_i,
        ps2_dat  => ps2_dat_i,
        clk_sync => open,
        clk_fall => sync_clk_fall,
        dat_sync => sync_dat
    );

    u_rx : entity work.ps2_receiver
    port map (
        clk       => clk_50m_i,
        clk_fall  => sync_clk_fall,
        dat_sync  => sync_dat,
        scan_code => rx_scan_code,
        valid     => rx_valid
    );

    fifo_full  <= '1' when fifo_count = FIFO_DEPTH else '0';
    fifo_empty <= '1' when fifo_count = 0 else '0';

    process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            fifo_wr_ptr    <= 0;
            fifo_rd_ptr    <= 0;
            fifo_count     <= 0;
            overflow_flag  <= '0';
            ctrl_irq_en    <= '0';
            reg_ack        <= '0';
            reg_rdata      <= (others => '0');
            for i in 0 to FIFO_DEPTH - 1 loop
                fifo_mem(i) <= (others => '0');
            end loop;
        elsif rising_edge(clk_50m_i) then
            reg_ack <= '0';

            if rx_valid = '1' then
                if fifo_full = '0' then
                    fifo_mem(fifo_wr_ptr) <= rx_scan_code;
                    if fifo_wr_ptr = FIFO_DEPTH - 1 then
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
                        when x"8" =>
                            ctrl_irq_en <= reg_dat_i(0);
                        when others =>
                            null;
                    end case;
                else
                    case reg_adr_i is
                        when x"0" =>
                            if fifo_empty = '0' then
                                reg_rdata <= x"000000" & fifo_mem(fifo_rd_ptr);
                            else
                                reg_rdata <= (others => '0');
                            end if;
                        when x"4" =>
                            reg_rdata <= (others => '0');
                            reg_rdata(0) <= not fifo_empty;
                            reg_rdata(1) <= overflow_flag;
                            reg_rdata(15 downto 8) <= std_logic_vector(to_unsigned(fifo_count, 8));
                        when x"8" =>
                            reg_rdata <= (others => '0');
                            reg_rdata(0) <= ctrl_irq_en;
                        when others =>
                            reg_rdata <= (others => '0');
                    end case;

                    if reg_adr_i = x"0" then
                        if fifo_empty = '0' then
                            if fifo_rd_ptr = FIFO_DEPTH - 1 then
                                fifo_rd_ptr <= 0;
                            else
                                fifo_rd_ptr <= fifo_rd_ptr + 1;
                            end if;
                            fifo_count <= fifo_count - 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    reg_ack_o <= reg_ack;
    reg_dat_o <= reg_rdata;
    ps2_valid_o <= rx_valid;
    ps2_scancode_o <= rx_scan_code;
    irq_o <= '1' when ctrl_irq_en = '1' and fifo_empty = '0' else '0';

end rtl;
