-- ps2_controller.vhd — PS/2 键盘控制器 (FIFO + 寄存器接口)
--
-- 包装 Exp8 的 ps2_sync + ps2_receiver，添加:
--   - 16-entry × 8-bit FIFO 缓冲扫描码
--   - 寄存器接口 (适配 Phase 3 的 wb_intercon)
--   - IRQ 输出 (data_ready 中断)
--
-- 寄存器映射 (偏移量, 字节地址):
--   0x00: DATA (读 = pop FIFO, 返回扫描码)
--   0x04: STATUS [0]=data_ready, [1]=overflow, [15:8]=fifo_count
--   0x08: CTRL   [0]=irq_enable

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ps2_controller is
    port (
        clk_50m_i   : in  std_logic;
        rst_n_i     : in  std_logic;

        -- PS/2 物理接口
        ps2_clk_i   : in  std_logic;
        ps2_dat_i   : in  std_logic;

        -- 寄存器接口 (32-bit 字地址)
        reg_adr_i   : in  std_logic_vector(3 downto 0);   -- 字节偏移量 [3:0]
        reg_dat_i   : in  std_logic_vector(31 downto 0);
        reg_dat_o   : out std_logic_vector(31 downto 0);
        reg_we_i    : in  std_logic;
        reg_stb_i   : in  std_logic;
        reg_ack_o   : out std_logic;

        -- 中断
        irq_o       : out std_logic
    );
end ps2_controller;

architecture rtl of ps2_controller is

    -- PS/2 接收器信号
    signal rx_scan_code  : std_logic_vector(7 downto 0);
    signal rx_valid      : std_logic;
    signal sync_clk_fall : std_logic;
    signal sync_dat      : std_logic;

    -- FIFO (16 entries × 8-bit, 环形缓冲)
    constant FIFO_DEPTH  : integer := 16;
    type fifo_array_t is array (0 to FIFO_DEPTH - 1) of std_logic_vector(7 downto 0);
    signal fifo_mem      : fifo_array_t := (others => (others => '0'));
    signal fifo_wr_ptr   : integer range 0 to FIFO_DEPTH - 1 := 0;
    signal fifo_rd_ptr   : integer range 0 to FIFO_DEPTH - 1 := 0;
    signal fifo_count    : integer range 0 to FIFO_DEPTH := 0;
    signal fifo_full     : std_logic;
    signal fifo_empty    : std_logic;

    -- 寄存器
    signal ctrl_irq_en   : std_logic := '0';
    signal overflow_flag : std_logic := '0';

    -- 寄存器读响应
    signal reg_ack       : std_logic := '0';
    signal reg_rdata     : std_logic_vector(31 downto 0) := (others => '0');

begin

    -- ============================================================
    -- PS/2 同步器 (Exp8, 已验证)
    -- ============================================================
    u_sync : entity work.ps2_sync
    port map (
        clk      => clk_50m_i,
        ps2_clk  => ps2_clk_i,
        ps2_dat  => ps2_dat_i,
        clk_fall => sync_clk_fall,
        dat_sync => sync_dat
    );

    -- ============================================================
    -- PS/2 接收器 (Exp8, 已验证)
    -- ============================================================
    u_rx : entity work.ps2_receiver
    port map (
        clk       => clk_50m_i,
        clk_fall  => sync_clk_fall,
        dat_sync  => sync_dat,
        scan_code => rx_scan_code,
        valid     => rx_valid
    );

    -- ============================================================
    -- FIFO 状态
    -- ============================================================
    fifo_full  <= '1' when fifo_count = FIFO_DEPTH else '0';
    fifo_empty <= '1' when fifo_count = 0 else '0';

    -- ============================================================
    -- FIFO 写入 (PS/2 接收器 → FIFO)
    -- ============================================================
    process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            fifo_wr_ptr <= 0;
            fifo_rd_ptr <= 0;
            fifo_count  <= 0;
            overflow_flag <= '0';
            for i in 0 to FIFO_DEPTH - 1 loop
                fifo_mem(i) <= (others => '0');
            end loop;
        elsif rising_edge(clk_50m_i) then
            -- 写入
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

            -- 读取 (当 reg_stb 且 reg_we=0 且 addr=0x00 时触发)
            if reg_stb_i = '1' and reg_we_i = '0' and reg_adr_i = x"0" then
                if fifo_empty = '0' then
                    if fifo_rd_ptr = FIFO_DEPTH - 1 then
                        fifo_rd_ptr <= 0;
                    else
                        fifo_rd_ptr <= fifo_rd_ptr + 1;
                    end if;
                    fifo_count <= fifo_count - 1;
                end if;
            end if;

            -- 写 STATUS 寄存器 bit1 清除 overflow
            if reg_stb_i = '1' and reg_we_i = '1' and reg_adr_i = x"4" then
                if reg_dat_i(1) = '1' then
                    overflow_flag <= '0';
                end if;
            end if;
        end if;
    end process;

    -- ============================================================
    -- 寄存器读写
    -- ============================================================
    process(clk_50m_i)
    begin
        if rising_edge(clk_50m_i) then
            reg_ack <= '0';

            if reg_stb_i = '1' then
                reg_ack <= '1';

                if reg_we_i = '1' then
                    -- 写寄存器
                    case reg_adr_i is
                        when x"8" =>
                            ctrl_irq_en <= reg_dat_i(0);
                        when others =>
                            null;
                    end case;
                else
                    -- 读寄存器
                    case reg_adr_i is
                        when x"0" =>
                            -- 读 DATA: 返回 FIFO 顶部 (不 pop, pop 在上面处理)
                            if fifo_empty = '0' then
                                reg_rdata <= x"000000" & fifo_mem(fifo_rd_ptr);
                            else
                                reg_rdata <= (others => '0');
                            end if;
                        when x"4" =>
                            -- 读 STATUS
                            reg_rdata <= (others => '0');
                            reg_rdata(0)           <= not fifo_empty;  -- data_ready
                            reg_rdata(1)           <= overflow_flag;   -- overflow
                            reg_rdata(15 downto 8) <= std_logic_vector(to_unsigned(fifo_count, 8));
                        when x"8" =>
                            -- 读 CTRL
                            reg_rdata <= (0 => ctrl_irq_en, others => '0');
                        when others =>
                            reg_rdata <= (others => '0');
                    end case;
                end if;
            end if;
        end if;
    end process;

    reg_ack_o <= reg_ack;
    reg_dat_o <= reg_rdata;

    -- ============================================================
    -- 中断输出
    -- ============================================================
    irq_o <= '1' when ctrl_irq_en = '1' and fifo_empty = '0' else '0';

end rtl;
