-- sdram_ctrl.vhd — SDRAM 控制器 (ISSI IS42S16400J, 32-bit bus)
--
-- 功能:
--   - Wishbone Classic slave (CPU 50MHz 侧, 内部 2-FF 同步)
--   - SDRAM 状态机跑在 100MHz
--   - 自动刷新管理 (7.8125us 间隔)
--   - CAS Latency 3, Burst Length 1 (8 separate READ commands for burst)
--   - Wishbone burst support via wb_cti_i (cti="010" = incrementing burst)
--   - Burst mode: 8 words latched once, async FIFO returns data to CPU
--   - Single-word mode: original toggle-based CDC handshake (unchanged)
--
-- 地址映射 (25-bit word address, aligned to Terasic reference controller):
--   bank = {addr[24], addr[10]}
--   row  = addr[23:11]
--   col  = addr[9:0]
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
        wb_cti_i    : in  std_logic_vector(2 downto 0);

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
    constant CMD_NOP      : std_logic_vector(3 downto 0) := "0111";
    constant CMD_DESEL    : std_logic_vector(3 downto 0) := "1111";
    constant CMD_ACTIVE   : std_logic_vector(3 downto 0) := "0011";
    constant CMD_READ     : std_logic_vector(3 downto 0) := "0101";
    constant CMD_WRITE    : std_logic_vector(3 downto 0) := "0100";
    constant CMD_PRECHG   : std_logic_vector(3 downto 0) := "0010";
    constant CMD_AUTO_REF : std_logic_vector(3 downto 0) := "0001";
    constant CMD_LOAD_MOD : std_logic_vector(3 downto 0) := "0000";

    constant INIT_WAIT_CYCLES : natural := 20000;
    constant REFRESH_INTERVAL : natural := 781;
    constant BURST_WORDS      : natural := 8;

    type state_t is (
        S_INIT, S_PRECHG_ALL, S_INIT_REFRESH, S_LOAD_MODE,
        S_IDLE, S_AUTO_REFRESH,
        S_ACTIVATE, S_TRCD_WAIT,
        S_READ_WAIT, S_READ_CAPTURE,
        S_WRITE_SETUP, S_WRITE_CMD, S_WRITE_WAIT, S_WRITE_RECOVERY,
        S_PRECHARGE, S_TRP_WAIT,
        S_PRECHG_WAIT, S_REF_WAIT, S_MODE_WAIT,
        -- Burst read states
        S_BURST_TRCD_WAIT, S_BURST_READ, S_BURST_CAS_WAIT,
        S_BURST_CAPTURE, S_BURST_PRECHARGE, S_BURST_TRP_WAIT
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

    -- Single-word CDC: toggle handshake (original)
    signal req_toggle_cpu : std_logic;
    signal req_toggle_sync : std_logic_vector(2 downto 0);
    signal req_seen_100m   : std_logic;
    signal req_fire_100m   : std_logic;
    signal req_busy_cpu    : std_logic;
    signal req_valid   : std_logic;
    signal req_shadow_adr : std_logic_vector(24 downto 0);
    signal req_shadow_dat : std_logic_vector(31 downto 0);
    signal req_shadow_we  : std_logic;
    signal req_shadow_sel : std_logic_vector(3 downto 0);
    signal req_adr     : std_logic_vector(24 downto 0);
    signal req_dat     : std_logic_vector(31 downto 0);
    signal req_we      : std_logic;
    signal req_sel     : std_logic_vector(3 downto 0);
    signal req_accept_toggle_100m : std_logic;
    signal req_accept_toggle_sync : std_logic_vector(2 downto 0);
    signal req_accept_seen_cpu    : std_logic;
    signal req_accept_pulse_cpu   : std_logic;

    signal ack_toggle_100m : std_logic;
    signal ack_toggle_sync : std_logic_vector(2 downto 0);
    signal ack_seen_cpu    : std_logic;
    signal wb_ack_pulse    : std_logic;

    -- Burst CDC: async FIFO + burst request latch
    signal burst_req_cpu      : std_logic;
    signal burst_req_shadow_adr : std_logic_vector(24 downto 0);
    signal burst_busy_cpu     : std_logic;

    signal burst_toggle_cpu   : std_logic;
    signal burst_toggle_sync  : std_logic_vector(2 downto 0);
    signal burst_seen_100m    : std_logic;
    signal burst_fire_100m    : std_logic;
    signal burst_valid        : std_logic;
    signal burst_adr          : std_logic_vector(24 downto 0);
    signal burst_col_cnt      : unsigned(2 downto 0);

    -- Async FIFO
    signal fifo_wr_en    : std_logic;
    signal fifo_wr_data  : std_logic_vector(31 downto 0);
    signal fifo_wr_full  : std_logic;
    signal fifo_rd_en    : std_logic;
    signal fifo_rd_data  : std_logic_vector(31 downto 0);
    signal fifo_rd_empty : std_logic;

    -- CPU side burst pop tracking
    signal burst_pop_cnt : unsigned(2 downto 0);
    signal burst_active  : std_logic;

begin

    -- ================================================================
    -- Async FIFO instantiation
    -- ================================================================
    u_fifo : entity work.async_fifo
    generic map (
        DWIDTH => 32,
        DEPTH  => 8
    )
    port map (
        wr_clk_i   => clk_sdram_i,
        wr_rst_n_i => rst_sdram_n,
        wr_en_i    => fifo_wr_en,
        wr_data_i  => fifo_wr_data,
        wr_full_o  => fifo_wr_full,
        rd_clk_i   => clk_cpu_i,
        rd_rst_n_i => rst_n_i,
        rd_en_i    => fifo_rd_en,
        rd_data_o  => fifo_rd_data,
        rd_empty_o => fifo_rd_empty
    );

    -- ================================================================
    -- CPU 侧请求锁存 (single-word + burst)
    -- ================================================================
    p_req_cpu : process (clk_cpu_i, rst_n_i)
        variable busy_v     : std_logic;
        variable burst_v    : std_logic;
        variable is_burst_v : std_logic;
    begin
        if rst_n_i = '0' then
            req_toggle_cpu <= '0';
            req_busy_cpu   <= '0';
            req_shadow_adr <= (others => '0');
            req_shadow_dat <= (others => '0');
            req_shadow_we  <= '0';
            req_shadow_sel <= (others => '0');
            burst_req_cpu  <= '0';
            burst_req_shadow_adr <= (others => '0');
            burst_busy_cpu <= '0';
            burst_toggle_cpu <= '0';
        elsif rising_edge(clk_cpu_i) then
            busy_v  := req_busy_cpu;
            burst_v := burst_busy_cpu;

            if req_accept_pulse_cpu = '1' then
                busy_v := '0';
            end if;

            -- Burst done: burst_pop_cnt wraps to 0 after 7 pops
            if burst_active = '1' and burst_pop_cnt = 7 and fifo_rd_en = '1' then
                burst_v := '0';
            end if;

            is_burst_v := '0';
            if wb_cti_i = "010" and wb_we_i = '0' then
                is_burst_v := '1';
            end if;

            if (wb_stb_i = '1') and (wb_cyc_i = '1') then
                if is_burst_v = '1' and burst_v = '0' then
                    -- Burst request: latch once
                    burst_req_shadow_adr <= wb_adr_i;
                    burst_req_cpu  <= '1';
                    burst_toggle_cpu <= not burst_toggle_cpu;
                    burst_v := '1';
                elsif is_burst_v = '0' and busy_v = '0' then
                    -- Single-word request
                    req_shadow_adr <= wb_adr_i;
                    req_shadow_dat <= wb_dat_i;
                    req_shadow_we  <= wb_we_i;
                    req_shadow_sel <= wb_sel_i;
                    req_toggle_cpu <= not req_toggle_cpu;
                    busy_v := '1';
                end if;
            end if;

            -- Clear burst req once 100MHz side has latched it
            if burst_fire_100m = '1' then
                burst_req_cpu <= '0';
            end if;

            req_busy_cpu   <= busy_v;
            burst_busy_cpu <= burst_v;
        end if;
    end process;

    -- ================================================================
    -- Burst toggle CDC (50MHz → 100MHz)
    -- ================================================================
    p_sync_burst : process (clk_sdram_i, rst_sdram_n)
    begin
        if rst_sdram_n = '0' then
            burst_toggle_sync <= (others => '0');
            burst_seen_100m   <= '0';
        elsif rising_edge(clk_sdram_i) then
            burst_toggle_sync <= burst_toggle_sync(1 downto 0) & burst_toggle_cpu;
            burst_seen_100m   <= burst_toggle_sync(2);
        end if;
    end process;

    burst_fire_100m <= burst_toggle_sync(2) xor burst_seen_100m;

    -- ================================================================
    -- Single-word CDC sync (unchanged from original)
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
            req_accept_toggle_100m <= '0';
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
                req_accept_toggle_100m <= not req_accept_toggle_100m;
            elsif (state = S_TRP_WAIT) and (trcd_cnt = 1) then
                req_valid <= '0';
            end if;
        end if;
    end process;

    p_sync_req_accept : process (clk_cpu_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            req_accept_toggle_sync <= (others => '0');
            req_accept_seen_cpu    <= '0';
        elsif rising_edge(clk_cpu_i) then
            req_accept_toggle_sync <= req_accept_toggle_sync(1 downto 0) & req_accept_toggle_100m;
            req_accept_seen_cpu    <= req_accept_toggle_sync(2);
        end if;
    end process;

    req_accept_pulse_cpu <= req_accept_toggle_sync(2) xor req_accept_seen_cpu;

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

    -- ================================================================
    -- CPU-side ack/dat mux (single-word vs burst)
    -- ================================================================
    burst_active <= burst_busy_cpu;

    -- Burst pop: when burst active, stb asserted, FIFO not empty
    fifo_rd_en <= '1' when burst_active = '1' and wb_stb_i = '1' and
                          wb_cyc_i = '1' and fifo_rd_empty = '0'
                  else '0';

    p_burst_pop_cnt : process (clk_cpu_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            burst_pop_cnt <= (others => '0');
        elsif rising_edge(clk_cpu_i) then
            if burst_active = '0' then
                burst_pop_cnt <= (others => '0');
            elsif fifo_rd_en = '1' then
                burst_pop_cnt <= burst_pop_cnt + 1;
            end if;
        end if;
    end process;

    -- Ack mux: burst pop ack or single-word toggle ack
    wb_ack_o <= fifo_rd_en when burst_active = '1' else wb_ack_pulse;

    -- Data mux: FIFO data for burst, synced SDRAM data for single-word
    wb_dat_o <= fifo_rd_data when burst_active = '1' else rd_data_cpu_ff2;

    wb_err_o <= '0';

    -- ================================================================
    -- SDRAM 状态机 (100MHz, with burst support)
    -- ================================================================
    p_sdram : process (clk_sdram_i, rst_sdram_n)
        variable cmd_v     : std_logic_vector(3 downto 0);
        variable do_burst  : std_logic;
        variable burst_col : unsigned(9 downto 0);
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
            burst_valid  <= '0';
            burst_adr    <= (others => '0');
            burst_col_cnt <= (others => '0');
            fifo_wr_en   <= '0';
            fifo_wr_data <= (others => '0');
        elsif rising_edge(clk_sdram_i) then
            dram_cke <= '1';
            dq_oe    <= '0';
            cmd_v    := CMD_NOP;
            dram_dqm <= (others => '0');
            fifo_wr_en <= '0';

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
                    else
                        -- Priority: burst > single-word
                        if burst_fire_100m = '1' then
                            burst_valid <= '1';
                            burst_adr   <= burst_req_shadow_adr;
                            -- Don't start yet — need burst_adr registered
                        elsif burst_valid = '1' then
                            addr_r  <= burst_adr;
                            we_r    <= '0';
                            ba_r    <= burst_adr(24) & burst_adr(10);
                            row_r   <= burst_adr(23 downto 11);
                            col_r   <= burst_adr(9 downto 0);
                            burst_col_cnt <= (others => '0');
                            state   <= S_ACTIVATE;
                        elsif req_valid = '1' then
                            addr_r    <= req_adr;
                            we_r      <= req_we;
                            wr_data_r <= req_dat;
                            sel_r     <= req_sel;
                            ba_r      <= req_adr(24) & req_adr(10);
                            row_r     <= req_adr(23 downto 11);
                            col_r     <= req_adr(9 downto 0);
                            state     <= S_ACTIVATE;
                        end if;
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
                    -- Route to burst or single-word path after tRCD
                    if burst_valid = '1' then
                        state <= S_BURST_TRCD_WAIT;
                    else
                        state <= S_TRCD_WAIT;
                    end if;

                -- ── Single-word path (unchanged logic) ──
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
                    if cas_cnt = 4 then
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
                        burst_valid <= '0';
                        ack_toggle_100m <= not ack_toggle_100m;
                        state <= S_IDLE;
                    end if;

                -- ── Burst read path ──
                when S_BURST_TRCD_WAIT =>
                    trcd_cnt <= trcd_cnt + 1;
                    if trcd_cnt = 1 then
                        state   <= S_BURST_READ;
                        cas_cnt <= (others => '0');
                    end if;

                when S_BURST_READ =>
                    if cas_cnt = 0 then
                        burst_col := unsigned(col_r) + resize(burst_col_cnt, 10);
                        cmd_v := CMD_READ;
                        dram_addr <= "000" & std_logic_vector(burst_col);
                        dram_ba   <= ba_r;
                        dram_dqm  <= (others => '0');
                    end if;
                    if cas_cnt = 4 then
                        state <= S_BURST_CAPTURE;
                    end if;
                    cas_cnt <= cas_cnt + 1;

                when S_BURST_CAPTURE =>
                    fifo_wr_en   <= '1';
                    fifo_wr_data <= dram_dq;
                    if burst_col_cnt = BURST_WORDS - 1 then
                        state <= S_BURST_PRECHARGE;
                    else
                        burst_col_cnt <= burst_col_cnt + 1;
                        state <= S_BURST_READ;
                        cas_cnt <= (others => '0');
                    end if;

                when S_BURST_PRECHARGE =>
                    cmd_v     := CMD_PRECHG;
                    dram_ba   <= ba_r;
                    dram_addr <= (others => '0');
                    trcd_cnt  <= (others => '0');
                    state     <= S_BURST_TRP_WAIT;

                when S_BURST_TRP_WAIT =>
                    trcd_cnt <= trcd_cnt + 1;
                    if trcd_cnt = 1 then
                        burst_valid <= '0';
                        state <= S_IDLE;
                    end if;

                when others => null;

            end case;
        end if;

        cmd <= cmd_v;
    end process;

    dram_cs_n  <= cmd(3);
    dram_ras_n <= cmd(2);
    dram_cas_n <= cmd(1);
    dram_we_n  <= cmd(0);
    dram_dq    <= wr_data_r when dq_oe = '1' else (others => 'Z');

end architecture rtl;
