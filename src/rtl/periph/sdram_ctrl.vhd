-- sdram_ctrl.vhd — SDRAM 控制器 (ISSI IS42S16400J, 32-bit bus)
--
-- 功能:
--   - Wishbone Classic slave (CPU 50MHz 侧, 内部 2-FF 同步)
--   - SDRAM 状态机跑在 100MHz
--   - 自动刷新管理 (7.8125us 间隔)
--   - CAS Latency 3, Burst Length 1
--
-- 地址映射 (CPU 字地址 25-bit):
--   [24]    = bank[1], [23] = bank[0]
--   [22:10] = row[12:0]
--   [9:0]   = col[9:0]
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_ctrl is
    port (
        -- 50MHz CPU 时钟域 (Wishbone slave)
        clk_cpu_i   : in  std_logic;
        rst_n_i     : in  std_logic;

        -- Wishbone slave
        wb_adr_i    : in  std_logic_vector(24 downto 0);
        wb_dat_i    : in  std_logic_vector(31 downto 0);
        wb_dat_o    : out std_logic_vector(31 downto 0);
        wb_we_i     : in  std_logic;
        wb_sel_i    : in  std_logic_vector(3 downto 0);
        wb_stb_i    : in  std_logic;
        wb_cyc_i    : in  std_logic;
        wb_ack_o    : out std_logic;
        wb_err_o    : out std_logic;

        -- 100MHz SDRAM 时钟域
        clk_sdram_i : in  std_logic;
        rst_sdram_n : in  std_logic;

        -- SDRAM 物理引脚
        dram_addr   : out std_logic_vector(12 downto 0);
        dram_ba     : out std_logic_vector(1 downto 0);
        dram_cas_n  : out std_logic;
        dram_cke    : out std_logic;
        dram_cs_n   : out std_logic;
        dram_dq     : inout std_logic_vector(31 downto 0);
        dram_dqm    : out std_logic_vector(3 downto 0);
        dram_ras_n  : out std_logic;
        dram_we_n   : out std_logic
    );
end entity sdram_ctrl;

architecture rtl of sdram_ctrl is

    -- cmd[3]=CS#, cmd[2]=RAS#, cmd[1]=CAS#, cmd[0]=WE#
    constant CMD_NOP      : std_logic_vector(3 downto 0) := "0111";  -- CS# asserted, all else idle
    constant CMD_DESEL    : std_logic_vector(3 downto 0) := "1111";  -- CS# deasserted (power save)
    constant CMD_ACTIVE   : std_logic_vector(3 downto 0) := "0011";
    constant CMD_READ     : std_logic_vector(3 downto 0) := "0101";
    constant CMD_WRITE    : std_logic_vector(3 downto 0) := "0100";
    constant CMD_PRECHG   : std_logic_vector(3 downto 0) := "0010";
    constant CMD_AUTO_REF : std_logic_vector(3 downto 0) := "0001";
    constant CMD_LOAD_MOD : std_logic_vector(3 downto 0) := "0000";

    constant INIT_WAIT_CYCLES : natural := 20000;  -- 200us / 10ns @100MHz (IS42S16400J spec)
    constant REFRESH_INTERVAL : natural := 781;  -- 7.8125us / 10ns @100MHz

    type state_t is (
        S_INIT, S_PRECHG_ALL, S_INIT_REFRESH, S_LOAD_MODE,
        S_IDLE, S_AUTO_REFRESH,
        S_ACTIVATE, S_TRCD_WAIT,
        S_READ_WAIT, S_READ_CAPTURE,
        S_WRITE_SETUP, S_WRITE_CMD, S_WRITE_WAIT, S_WRITE_RECOVERY, S_PRECHARGE, S_TRP_WAIT,
        S_PRECHG_WAIT, S_REF_WAIT, S_MODE_WAIT
    );

    signal state       : state_t;
    signal cmd         : std_logic_vector(3 downto 0);

    signal init_cnt    : unsigned(14 downto 0);
    signal ref_cnt     : unsigned(9 downto 0);
    signal refresh_cnt : unsigned(3 downto 0);

    signal cas_cnt     : unsigned(2 downto 0);
    signal trcd_cnt    : unsigned(1 downto 0);
    signal wait_cnt    : unsigned(2 downto 0);
    signal ref_init    : std_logic;

    signal wr_data_r   : std_logic_vector(31 downto 0);
    signal rd_data_r   : std_logic_vector(31 downto 0);
    signal rd_data_hold_100m : std_logic_vector(31 downto 0);
    signal rd_data_cpu_ff1   : std_logic_vector(31 downto 0);
    signal rd_data_cpu_ff2   : std_logic_vector(31 downto 0);
    signal addr_r      : std_logic_vector(24 downto 0);
    signal ba_r        : std_logic_vector(1 downto 0);
    signal row_r       : std_logic_vector(12 downto 0);
    signal col_r       : std_logic_vector(9 downto 0);
    signal we_r        : std_logic;
    signal sel_r       : std_logic_vector(3 downto 0);

    signal dq_oe       : std_logic;

    -- 请求锁存: CPU 侧在 stb 脉冲到来时抓住完整请求，再用 toggle 过 CDC。
    -- 这样不会在前一笔 ack 返回的边界丢掉紧跟着的下一笔请求。
    signal req_toggle_cpu : std_logic;
    signal req_toggle_sync : std_logic_vector(2 downto 0);
    signal req_seen_100m   : std_logic;
    signal req_fire_100m   : std_logic;
    signal req_valid   : std_logic;
    signal req_shadow_adr : std_logic_vector(24 downto 0);
    signal req_shadow_dat : std_logic_vector(31 downto 0);
    signal req_shadow_we  : std_logic;
    signal req_shadow_sel : std_logic_vector(3 downto 0);
    signal req_adr     : std_logic_vector(24 downto 0);
    signal req_dat     : std_logic_vector(31 downto 0);
    signal req_we      : std_logic;
    signal req_sel     : std_logic_vector(3 downto 0);

    -- Ack 回传 (100MHz → 50MHz): 也使用 toggle，避免窄脉冲跨域丢失。
    signal ack_toggle_100m : std_logic;
    signal ack_toggle_sync : std_logic_vector(2 downto 0);
    signal ack_seen_cpu    : std_logic;
    signal wb_ack_pulse    : std_logic;

begin

    -- ================================================================
    -- CPU 侧请求锁存
    -- ================================================================
    p_req_cpu : process (clk_cpu_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            req_toggle_cpu <= '0';
            req_shadow_adr <= (others => '0');
            req_shadow_dat <= (others => '0');
            req_shadow_we  <= '0';
            req_shadow_sel <= (others => '0');
        elsif rising_edge(clk_cpu_i) then
            if wb_stb_i = '1' and wb_cyc_i = '1' then
                req_shadow_adr <= wb_adr_i;
                req_shadow_dat <= wb_dat_i;
                req_shadow_we  <= wb_we_i;
                req_shadow_sel <= wb_sel_i;
                req_toggle_cpu <= not req_toggle_cpu;
            end if;
        end if;
    end process;

    -- ================================================================
    -- 请求 / 响应 toggle 跨时钟域同步
    -- ================================================================
    p_sync_req : process (clk_sdram_i, rst_sdram_n)
    begin
        if rst_sdram_n = '0' then
            req_toggle_sync <= (others => '0');
            req_seen_100m   <= '0';
        elsif rising_edge(clk_sdram_i) then
            req_toggle_sync <= req_toggle_sync(1 downto 0) & req_toggle_cpu;
            req_seen_100m   <= req_toggle_sync(2);
        end if;
    end process;

    req_fire_100m <= req_toggle_sync(2) xor req_seen_100m;

    p_req_latch : process (clk_sdram_i, rst_sdram_n)
    begin
        if rst_sdram_n = '0' then
            req_valid <= '0';
            req_adr   <= (others => '0');
            req_dat   <= (others => '0');
            req_we    <= '0';
            req_sel   <= (others => '0');
        elsif rising_edge(clk_sdram_i) then
            if req_fire_100m = '1' then
                req_valid <= '1';
                req_adr   <= req_shadow_adr;
                req_dat   <= req_shadow_dat;
                req_we    <= req_shadow_we;
                req_sel   <= req_shadow_sel;
            elsif (state = S_TRP_WAIT) and (trcd_cnt = 1) then
                req_valid <= '0';
            end if;
        end if;
    end process;

    p_sync_ack : process (clk_cpu_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            ack_toggle_sync <= (others => '0');
            ack_seen_cpu    <= '0';
            rd_data_cpu_ff1 <= (others => '0');
            rd_data_cpu_ff2 <= (others => '0');
        elsif rising_edge(clk_cpu_i) then
            ack_toggle_sync <= ack_toggle_sync(1 downto 0) & ack_toggle_100m;
            ack_seen_cpu    <= ack_toggle_sync(2);
            rd_data_cpu_ff1 <= rd_data_hold_100m;
            rd_data_cpu_ff2 <= rd_data_cpu_ff1;
        end if;
    end process;

    wb_ack_pulse <= ack_toggle_sync(2) xor ack_seen_cpu;

    wb_ack_o <= wb_ack_pulse;
    wb_err_o <= '0';

    -- ================================================================
    -- SDRAM 状态机
    -- ================================================================
    p_sdram : process (clk_sdram_i, rst_sdram_n)
        variable cmd_v : std_logic_vector(3 downto 0);
    begin
        if rst_sdram_n = '0' then
            state        <= S_INIT;
            cmd_v        := CMD_NOP;
            wait_cnt     <= (others => '0');
            ref_init     <= '0';
            init_cnt     <= (others => '0');
            ref_cnt      <= to_unsigned(REFRESH_INTERVAL, 10);
            refresh_cnt  <= (others => '0');
            cas_cnt      <= (others => '0');
            trcd_cnt     <= (others => '0');
            ack_toggle_100m <= '0';
            dq_oe        <= '0';
            wr_data_r    <= (others => '0');
            rd_data_r    <= (others => '0');
            rd_data_hold_100m <= (others => '0');
            addr_r       <= (others => '0');
            ba_r         <= (others => '0');
            row_r        <= (others => '0');
            col_r        <= (others => '0');
            we_r         <= '0';
            sel_r        <= (others => '0');
            dram_cke     <= '0';
        elsif rising_edge(clk_sdram_i) then
            dram_cke <= '1';
            dq_oe    <= '0';
            cmd_v    := CMD_NOP;
            dram_dqm <= (others => '0');

            case state is

                when S_INIT =>
                    init_cnt <= init_cnt + 1;
                    if init_cnt = INIT_WAIT_CYCLES - 1 then
                        state <= S_PRECHG_ALL;
                    end if;

                when S_PRECHG_ALL =>
                    cmd_v    := CMD_PRECHG;
                    dram_addr <= (10 => '1', others => '0');
                    dram_ba   <= (others => '0');
                    wait_cnt  <= (others => '0');
                    refresh_cnt <= (others => '0');
                    state    <= S_PRECHG_WAIT;

                when S_PRECHG_WAIT =>
                    wait_cnt <= wait_cnt + 1;
                    if wait_cnt = 1 then
                        state <= S_INIT_REFRESH;
                    end if;

                when S_INIT_REFRESH =>
                    cmd_v := CMD_AUTO_REF;
                    refresh_cnt <= refresh_cnt + 1;
                    wait_cnt <= (others => '0');
                    ref_init <= '1';
                    state <= S_REF_WAIT;

                when S_REF_WAIT =>
                    wait_cnt <= wait_cnt + 1;
                    if wait_cnt = 6 then
                        if ref_init = '1' then
                            if refresh_cnt = 8 then
                                state <= S_LOAD_MODE;
                            else
                                state <= S_INIT_REFRESH;
                            end if;
                        else
                            state <= S_IDLE;
                        end if;
                    end if;

                when S_LOAD_MODE =>
                    cmd_v    := CMD_LOAD_MOD;
                    dram_addr <= "0000000110000";
                    dram_ba   <= "00";
                    wait_cnt  <= (others => '0');
                    state    <= S_MODE_WAIT;

                when S_MODE_WAIT =>
                    wait_cnt <= wait_cnt + 1;
                    if wait_cnt = 1 then
                        state <= S_IDLE;
                    end if;
                    ref_cnt  <= to_unsigned(REFRESH_INTERVAL, 10);

                when S_IDLE =>
                    if ref_cnt = 0 then
                        state <= S_AUTO_REFRESH;
                    elsif req_valid = '1' then
                        addr_r    <= req_adr;
                        we_r      <= req_we;
                        wr_data_r <= req_dat;
                        sel_r     <= req_sel;
                        ba_r      <= req_adr(24 downto 23);
                        row_r     <= req_adr(22 downto 10);
                        col_r     <= req_adr(9 downto 0);
                        state     <= S_ACTIVATE;
                    end if;
                    ref_cnt <= ref_cnt - 1;

                when S_AUTO_REFRESH =>
                    cmd_v   := CMD_AUTO_REF;
                    wait_cnt <= (others => '0');
                    ref_init <= '0';
                    ref_cnt <= to_unsigned(REFRESH_INTERVAL, 10);
                    state   <= S_REF_WAIT;

                when S_ACTIVATE =>
                    cmd_v    := CMD_ACTIVE;
                    dram_ba  <= ba_r;
                    dram_addr <= row_r;
                    trcd_cnt <= (others => '0');
                    state <= S_TRCD_WAIT;

                when S_TRCD_WAIT =>
                    trcd_cnt <= trcd_cnt + 1;
                    if trcd_cnt = 1 then
                        if we_r = '1' then
                            state <= S_WRITE_SETUP;
                        else
                            state <= S_READ_WAIT;
                            cas_cnt <= (others => '0');
                        end if;
                    end if;

                when S_READ_WAIT =>
                    if cas_cnt = 0 then
                        cmd_v := CMD_READ;
                        dram_addr <= "000" & col_r;
                        dram_ba       <= ba_r;
                        dram_dqm      <= (others => '0');
                    end if;
                    -- READ is issued when cas_cnt=0. On hardware the 3rd internal
                    -- edge proved too early, while the original 4th-edge sampling
                    -- at least pushed the first failing word later. Keep the
                    -- controller-side capture on the 4th internal edge and tune the
                    -- external DRAM clock phase separately in the PLL wrapper.
                    if cas_cnt = 3 then
                        state <= S_READ_CAPTURE;
                    end if;
                    cas_cnt <= cas_cnt + 1;

                when S_READ_CAPTURE =>
                    rd_data_r <= dram_dq;
                    rd_data_hold_100m <= dram_dq;
                    state     <= S_PRECHARGE;

                when S_WRITE_SETUP =>
                    dq_oe    <= '1';
                    dram_dqm <= not sel_r;
                    state    <= S_WRITE_CMD;

                when S_WRITE_CMD =>
                    cmd_v     := CMD_WRITE;
                    dram_addr <= "000" & col_r;
                    dram_ba   <= ba_r;
                    dram_dqm  <= not sel_r;
                    dq_oe     <= '1';
                    state     <= S_WRITE_WAIT;

                when S_WRITE_WAIT =>
                    dq_oe     <= '1';
                    state     <= S_WRITE_RECOVERY;

                when S_WRITE_RECOVERY =>
                    state     <= S_PRECHARGE;

                when S_PRECHARGE =>
                    cmd_v    := CMD_PRECHG;
                    dram_ba  <= ba_r;
                    dram_addr <= (others => '0');
                    trcd_cnt <= (others => '0');
                    state    <= S_TRP_WAIT;

                when S_TRP_WAIT =>
                    trcd_cnt <= trcd_cnt + 1;
                    if trcd_cnt = 1 then
                        ack_toggle_100m <= not ack_toggle_100m;
                        state <= S_IDLE;
                    end if;

            end case;
        end if;

        cmd <= cmd_v;
    end process;

    dram_cs_n  <= cmd(3);
    dram_ras_n <= cmd(2);
    dram_cas_n <= cmd(1);
    dram_we_n  <= cmd(0);
    dram_dq    <= wr_data_r when dq_oe = '1' else (others => 'Z');
    wb_dat_o   <= rd_data_cpu_ff2;

end architecture rtl;
