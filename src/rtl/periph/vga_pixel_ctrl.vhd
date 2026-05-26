-- vga_pixel_ctrl.vhd — VGA pixel-mode controller (640x480 @ 60Hz, RGB332)
--
-- Reads an 8-bit RGB332 framebuffer from SDRAM via burst reads,
-- displays on VGA at 640x480 @ 60Hz. Dual line-buffer (ping-pong)
-- decouples SDRAM read latency from pixel output.
--
-- Line buffers: 160 words x 32-bit (4 pixels per word) in M9K.
-- Display side reads one word per 4 pixel clocks (25 MHz).
-- Fetch side writes one word per burst return cycle (50 MHz domain).
--
-- Register map (Wishbone byte address, word-aligned):
--   0x00  mode        R/W  bit 0: enable pixel mode
--   0x04  fb_base     R/W  [26:2] SDRAM word address of framebuffer
--   0x08  status      R    bit 0: in vblank
--   0x0C  debug0      R    fetch FSM state / word / burst counters
--   0x10  debug1      R    active fetch line / pending next line
--   0x14  debug2      R    request and valid word counters
--   0x18  debug3      R    line-event and burst-done counters
--   0x1C  sample0     R    current display-side buffered word
--   0x20  sample1     R    current linebuf A read-data
--   0x24  sample2     R    current linebuf B read-data
--   0x28  sample3     R    rd/wr addresses and write enables
--
-- SDRAM interface: VGA burst-read port on sdram_ctrl.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library altera_mf;
use altera_mf.altera_mf_components.all;

entity vga_pixel_ctrl is
    port (
        clk_50m_i   : in  std_logic;
        rst_n_i     : in  std_logic;

        -- VGA DAC outputs
        vga_r_o     : out std_logic_vector(7 downto 0);
        vga_g_o     : out std_logic_vector(7 downto 0);
        vga_b_o     : out std_logic_vector(7 downto 0);
        vga_hs_o    : out std_logic;
        vga_vs_o    : out std_logic;
        vga_blank_o : out std_logic;
        vga_sync_o  : out std_logic;
        vga_clk_o   : out std_logic;

        -- Register interface (Wishbone-like)
        reg_adr_i   : in  std_logic_vector(15 downto 0);
        reg_dat_i   : in  std_logic_vector(31 downto 0);
        reg_dat_o   : out std_logic_vector(31 downto 0);
        reg_we_i    : in  std_logic;
        reg_stb_i   : in  std_logic;
        reg_ack_o   : out std_logic;
        mode_en_o   : out std_logic;

        -- SDRAM burst read request → sdram_ctrl VGA port
        vga_rd_adr_o  : out std_logic_vector(24 downto 0);
        vga_rd_req_o  : out std_logic;
        vga_rd_data_i : in  std_logic_vector(31 downto 0);
        vga_rd_valid_i: in  std_logic;
        vga_rd_done_i : in  std_logic
    );
end entity vga_pixel_ctrl;

architecture rtl of vga_pixel_ctrl is

    -- VGA 640x480 @ 60Hz timing
    constant H_TOTAL  : integer := 800;
    constant H_SYNC   : integer := 96;
    constant H_BP     : integer := 48;
    constant H_ACTIVE : integer := 640;
    constant V_TOTAL  : integer := 525;
    constant V_SYNC   : integer := 2;
    constant V_BP     : integer := 33;
    constant V_ACTIVE : integer := 480;

    constant LINE_WORDS : integer := 160;  -- 640 pixels / 4 pixels per word
    constant BURST_LEN  : integer := 8;

    -- 25 MHz pixel clock from 50 MHz toggle
    signal clk_25m : std_logic;

    -- VGA timing (25 MHz domain)
    signal h_count  : integer range 0 to H_TOTAL - 1;
    signal v_count  : integer range 0 to V_TOTAL - 1;
    signal video_on : std_logic;

    -- Registers (50 MHz domain)
    signal mode_en : std_logic;
    signal testpat_en : std_logic;
    signal fb_base : unsigned(24 downto 0);

    -- Line buffers: explicit dual-clock M9K to avoid Quartus mis-inferring
    -- the 50MHz write / 25MHz read path as combinational logic.
    signal linebuf_wr_addr : std_logic_vector(7 downto 0);
    signal linebuf_rd_addr : std_logic_vector(7 downto 0);
    signal linebuf_wr_data : std_logic_vector(31 downto 0);
    signal linebuf_a_q     : std_logic_vector(31 downto 0);
    signal linebuf_b_q     : std_logic_vector(31 downto 0);
    signal linebuf_a_wren  : std_logic;
    signal linebuf_b_wren  : std_logic;

    -- Ping-pong: '0' → A = display, B = fill; '1' → B = display, A = fill
    signal buf_sel : std_logic;

    -- Pixel read pipeline (25 MHz domain)
    signal rd_word_addr : integer range 0 to LINE_WORDS - 1;
    signal disp_word_q  : std_logic_vector(31 downto 0);
    signal px_vis_d     : integer range 0 to H_ACTIVE - 1;
    signal fb_video_d   : std_logic;

    -- Pipeline register for pixel color → DAC
    signal pixel_color : std_logic_vector(7 downto 0);

    -- SDRAM fetch FSM (50 MHz domain)
    type fetch_state_t is (F_IDLE, F_REQ, F_POP, F_NEXT_BURST, F_LINE_DONE);
    signal fetch_state    : fetch_state_t;
    signal fetch_line     : integer range 0 to V_ACTIVE + 1;  -- can go past V_ACTIVE briefly
    signal fetch_word_cnt : integer range 0 to LINE_WORDS - 1;
    signal fetch_burst_cnt : integer range 0 to BURST_LEN - 1;
    signal fetch_buf_sel  : std_logic;

    -- Visible-line fetch event crossing 25 MHz → 50 MHz
    signal line_req_toggle_25m : std_logic;
    signal line_req_toggle_sync : std_logic_vector(2 downto 0);
    signal line_req_seen_50m : std_logic;
    signal line_req_fire_50m : std_logic;
    signal line_fetch_shadow : unsigned(8 downto 0);
    signal line_fill_shadow  : std_logic;

    -- Debug counters (50 MHz domain)
    signal dbg_req_count       : unsigned(15 downto 0);
    signal dbg_valid_count     : unsigned(15 downto 0);
    signal dbg_line_evt_count  : unsigned(15 downto 0);
    signal dbg_burst_done_count: unsigned(15 downto 0);

    -- Register ack
    signal reg_ack_ff : std_logic;

begin

    linebuf_wr_addr <= std_logic_vector(to_unsigned(fetch_word_cnt, linebuf_wr_addr'length));
    linebuf_wr_data <= vga_rd_data_i;
    linebuf_a_wren <= '1' when (fetch_state = F_POP and vga_rd_valid_i = '1' and fetch_buf_sel = '0') else '0';
    linebuf_b_wren <= '1' when (fetch_state = F_POP and vga_rd_valid_i = '1' and fetch_buf_sel = '1') else '0';

    u_linebuf_a : altsyncram
    generic map (
        intended_device_family => "Cyclone IV E",
        lpm_type               => "altsyncram",
        operation_mode         => "DUAL_PORT",
        width_a                => 32,
        widthad_a              => 8,
        numwords_a             => 160,
        width_b                => 32,
        widthad_b              => 8,
        numwords_b             => 160,
        outdata_reg_b          => "UNREGISTERED",
        address_reg_b          => "CLOCK1",
        outdata_aclr_b         => "NONE",
        address_aclr_a         => "NONE",
        address_aclr_b         => "NONE",
        indata_aclr_a          => "NONE",
        wrcontrol_aclr_a       => "NONE",
        ram_block_type         => "M9K",
        read_during_write_mode_mixed_ports => "DONT_CARE"
    )
    port map (
        clock0    => clk_50m_i,
        clock1    => clk_25m,
        address_a => linebuf_wr_addr,
        address_b => linebuf_rd_addr,
        data_a    => linebuf_wr_data,
        wren_a    => linebuf_a_wren,
        q_b       => linebuf_a_q
    );

    u_linebuf_b : altsyncram
    generic map (
        intended_device_family => "Cyclone IV E",
        lpm_type               => "altsyncram",
        operation_mode         => "DUAL_PORT",
        width_a                => 32,
        widthad_a              => 8,
        numwords_a             => 160,
        width_b                => 32,
        widthad_b              => 8,
        numwords_b             => 160,
        outdata_reg_b          => "UNREGISTERED",
        address_reg_b          => "CLOCK1",
        outdata_aclr_b         => "NONE",
        address_aclr_a         => "NONE",
        address_aclr_b         => "NONE",
        indata_aclr_a          => "NONE",
        wrcontrol_aclr_a       => "NONE",
        ram_block_type         => "M9K",
        read_during_write_mode_mixed_ports => "DONT_CARE"
    )
    port map (
        clock0    => clk_50m_i,
        clock1    => clk_25m,
        address_a => linebuf_wr_addr,
        address_b => linebuf_rd_addr,
        data_a    => linebuf_wr_data,
        wren_a    => linebuf_b_wren,
        q_b       => linebuf_b_q
    );

    -- ================================================================
    -- 25 MHz pixel clock
    -- ================================================================
    p_clkdiv : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            clk_25m <= '0';
        elsif rising_edge(clk_50m_i) then
            clk_25m <= not clk_25m;
        end if;
    end process;
    vga_clk_o <= clk_25m;

    -- ================================================================
    -- Register interface (50 MHz)
    -- ================================================================
    p_reg : process(clk_50m_i, rst_n_i)
        variable adr : integer;
    begin
        if rst_n_i = '0' then
            mode_en    <= '0';
            testpat_en <= '0';
            fb_base    <= (others => '0');
            reg_ack_ff <= '0';
        elsif rising_edge(clk_50m_i) then
            reg_ack_ff <= '0';
            if reg_stb_i = '1' and reg_ack_ff = '0' then
                reg_ack_ff <= '1';
                adr := to_integer(unsigned(reg_adr_i(15 downto 2)));
                if reg_we_i = '1' then
                    case adr is
                        when 0 =>
                            mode_en    <= reg_dat_i(0);
                            testpat_en <= reg_dat_i(1);
                        when 1 => fb_base <= unsigned(reg_dat_i(26 downto 2));
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;
    reg_ack_o <= reg_ack_ff;
    mode_en_o <= mode_en;

    p_reg_rd : process(reg_adr_i, mode_en, fb_base, video_on,
                       fetch_state, fetch_line, fetch_word_cnt, fetch_burst_cnt,
                       fetch_buf_sel, line_fetch_shadow, line_fill_shadow,
                       dbg_req_count, dbg_valid_count, dbg_line_evt_count, dbg_burst_done_count,
                       disp_word_q, linebuf_a_q, linebuf_b_q,
                       linebuf_rd_addr, linebuf_wr_addr, linebuf_a_wren, linebuf_b_wren)
        variable adr : integer;
        variable state_code : std_logic_vector(2 downto 0);
    begin
        reg_dat_o <= (others => '0');
        adr := to_integer(unsigned(reg_adr_i(15 downto 2)));
        state_code := "000";
        case fetch_state is
            when F_IDLE       => state_code := "000";
            when F_REQ        => state_code := "001";
            when F_POP        => state_code := "010";
            when F_NEXT_BURST => state_code := "011";
            when F_LINE_DONE  => state_code := "100";
        end case;
        case adr is
            when 0 =>
                reg_dat_o(0) <= mode_en;
                reg_dat_o(1) <= testpat_en;
            when 1 => reg_dat_o(26 downto 2) <= std_logic_vector(fb_base);
            when 2 => reg_dat_o(0) <= not video_on;
            when 3 =>
                reg_dat_o(2 downto 0)   <= state_code;
                reg_dat_o(3)            <= fetch_buf_sel;
                reg_dat_o(11 downto 4)  <= std_logic_vector(to_unsigned(fetch_burst_cnt, 8));
                reg_dat_o(23 downto 12) <= std_logic_vector(to_unsigned(fetch_word_cnt, 12));
                reg_dat_o(24)           <= line_fill_shadow;
            when 4 =>
                reg_dat_o(8 downto 0)   <= std_logic_vector(to_unsigned(fetch_line, 9));
                reg_dat_o(17 downto 9)  <= std_logic_vector(line_fetch_shadow);
            when 5 =>
                reg_dat_o(15 downto 0)  <= std_logic_vector(dbg_req_count);
                reg_dat_o(31 downto 16) <= std_logic_vector(dbg_valid_count);
            when 6 =>
                reg_dat_o(15 downto 0)  <= std_logic_vector(dbg_line_evt_count);
                reg_dat_o(31 downto 16) <= std_logic_vector(dbg_burst_done_count);
            when 7 =>
                reg_dat_o <= disp_word_q;
            when 8 =>
                reg_dat_o <= linebuf_a_q;
            when 9 =>
                reg_dat_o <= linebuf_b_q;
            when 10 =>
                reg_dat_o(7 downto 0)   <= linebuf_rd_addr;
                reg_dat_o(15 downto 8)  <= linebuf_wr_addr;
                reg_dat_o(16)           <= linebuf_a_wren;
                reg_dat_o(17)           <= linebuf_b_wren;
            when others => null;
        end case;
    end process;

    -- ================================================================
    -- VGA timing (25 MHz domain)
    -- ================================================================
    p_timing : process(clk_25m, rst_n_i)
    begin
        if rst_n_i = '0' then
            h_count  <= 0;
            v_count  <= 0;
        elsif rising_edge(clk_25m) then
            if h_count = H_TOTAL - 1 then
                h_count <= 0;
                if v_count = V_TOTAL - 1 then
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
                end if;
            else
                h_count <= h_count + 1;
            end if;
        end if;
    end process;

    video_on <= '1' when
        h_count >= (H_SYNC + H_BP) and h_count < (H_SYNC + H_BP + H_ACTIVE) and
        v_count >= (V_SYNC + V_BP) and v_count < (V_SYNC + V_BP + V_ACTIVE)
        else '0';

    vga_hs_o   <= '0' when h_count < H_SYNC else '1';
    vga_vs_o   <= '0' when v_count < V_SYNC else '1';
    vga_blank_o <= video_on;
    -- Match the known-good Exp6/Exp7 behaviour on DE2-115:
    -- keep composite sync inactive during active video to avoid sync-on-green bias.
    vga_sync_o  <= '0' when (h_count >= H_SYNC and v_count >= V_SYNC) else '1';

    -- Swap buffers at start of each visible scanline
    p_bufswap : process(clk_25m, rst_n_i)
        variable vis_line : integer range 0 to V_ACTIVE - 1;
    begin
        if rst_n_i = '0' then
            buf_sel <= '0';
            line_req_toggle_25m <= '0';
            line_fetch_shadow <= (others => '0');
            line_fill_shadow <= '0';
        elsif rising_edge(clk_25m) then
            if h_count = 0 and v_count >= (V_SYNC + V_BP) and v_count < (V_SYNC + V_BP + V_ACTIVE) then
                vis_line := v_count - (V_SYNC + V_BP);
                if vis_line < V_ACTIVE - 1 then
                    line_fetch_shadow <= to_unsigned(vis_line + 1, line_fetch_shadow'length);
                else
                    line_fetch_shadow <= (others => '0');
                end if;
                line_fill_shadow <= buf_sel;
                line_req_toggle_25m <= not line_req_toggle_25m;
                buf_sel <= not buf_sel;
            end if;
        end if;
    end process;

    -- ================================================================
    -- Pixel output: read line buffer, shift out 4 pixels per word
    -- (25 MHz domain)
    -- ================================================================
    p_rd_addr : process(all)
        variable px_vis : integer range 0 to H_ACTIVE - 1;
    begin
        rd_word_addr <= 0;
        linebuf_rd_addr <= (others => '0');
        if video_on = '1' then
            px_vis := h_count - (H_SYNC + H_BP);
            rd_word_addr <= px_vis / 4;
            linebuf_rd_addr <= std_logic_vector(to_unsigned(px_vis / 4, linebuf_rd_addr'length));
        end if;
    end process;

    p_rd_pipe : process(clk_25m)
    begin
        if rising_edge(clk_25m) then
            if video_on = '1' then
                px_vis_d <= h_count - (H_SYNC + H_BP);
                if buf_sel = '0' then
                    disp_word_q <= linebuf_a_q;
                else
                    disp_word_q <= linebuf_b_q;
                end if;
            else
                px_vis_d <= 0;
                disp_word_q <= (others => '0');
            end if;
            fb_video_d <= video_on and mode_en and (not testpat_en);
        end if;
    end process;

    p_pixel_out : process(clk_25m, rst_n_i)
        variable pat_color : std_logic_vector(7 downto 0);
        variable px_vis    : integer range 0 to H_ACTIVE - 1;
        variable py_vis    : integer range 0 to V_ACTIVE - 1;
    begin
        if rst_n_i = '0' then
            pixel_color  <= (others => '0');
            vga_r_o      <= (others => '0');
            vga_g_o      <= (others => '0');
            vga_b_o      <= (others => '0');
        elsif rising_edge(clk_25m) then
            if video_on = '1' and mode_en = '1' and testpat_en = '1' then
                px_vis := h_count - (H_SYNC + H_BP);
                py_vis := v_count - (V_SYNC + V_BP);
                pat_color := x"12";

                if py_vis < 96 then
                    case px_vis / 80 is
                        when 0 => pat_color := x"E0";
                        when 1 => pat_color := x"F8";
                        when 2 => pat_color := x"FC";
                        when 3 => pat_color := x"1C";
                        when 4 => pat_color := x"1F";
                        when 5 => pat_color := x"03";
                        when 6 => pat_color := x"E3";
                        when others => pat_color := x"FF";
                    end case;
                elsif (px_vis < 8) or (px_vis >= H_ACTIVE - 8) or
                      (py_vis < 8) or (py_vis >= V_ACTIVE - 8) then
                    pat_color := x"FF";
                elsif ((px_vis / 32) mod 2) = ((py_vis / 32) mod 2) then
                    pat_color := x"49";
                else
                    pat_color := x"12";
                end if;

                pixel_color  <= pat_color;
            elsif fb_video_d = '1' then
                case px_vis_d mod 4 is
                    when 0 => pixel_color <= disp_word_q(7 downto 0);
                    when 1 => pixel_color <= disp_word_q(15 downto 8);
                    when 2 => pixel_color <= disp_word_q(23 downto 16);
                    when others => pixel_color <= disp_word_q(31 downto 24);
                end case;
            else
                pixel_color  <= (others => '0');
            end if;

            -- RGB332 → RGB888 expansion (1 pipeline stage)
            vga_r_o <= pixel_color(7 downto 5) & pixel_color(7 downto 5) & pixel_color(6) & pixel_color(5);
            vga_g_o <= pixel_color(4 downto 2) & pixel_color(4 downto 2) & pixel_color(3) & pixel_color(2);
            vga_b_o <= pixel_color(1 downto 0) & pixel_color(1 downto 0) &
                       pixel_color(1 downto 0) & pixel_color(1) & pixel_color(0);
        end if;
    end process;

    -- ================================================================
    -- Synchronize visible-line fetch event from 25 MHz → 50 MHz
    -- ================================================================
    p_sync_line_req : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            line_req_toggle_sync <= (others => '0');
            line_req_seen_50m <= '0';
        elsif rising_edge(clk_50m_i) then
            line_req_toggle_sync <= line_req_toggle_sync(1 downto 0) & line_req_toggle_25m;
            line_req_seen_50m <= line_req_toggle_sync(2);
        end if;
    end process;

    line_req_fire_50m <= line_req_toggle_sync(2) xor line_req_seen_50m;

    -- ================================================================
    -- SDRAM fetch FSM (50 MHz domain)
    -- Prefetches the NEXT scanline into the fill buffer.
    -- Triggered by new_line_pulse from VGA timing.
    -- ================================================================
    p_fetch : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            fetch_state    <= F_IDLE;
            fetch_line     <= 0;
            fetch_word_cnt <= 0;
            fetch_burst_cnt <= 0;
            fetch_buf_sel  <= '0';
            vga_rd_req_o   <= '0';
            vga_rd_adr_o   <= (others => '0');
            dbg_req_count <= (others => '0');
            dbg_valid_count <= (others => '0');
            dbg_line_evt_count <= (others => '0');
            dbg_burst_done_count <= (others => '0');
        elsif rising_edge(clk_50m_i) then
            vga_rd_req_o <= '0';

            if line_req_fire_50m = '1' then
                dbg_line_evt_count <= dbg_line_evt_count + 1;
            end if;

            case fetch_state is
                when F_IDLE =>
                    if line_req_fire_50m = '1' and mode_en = '1' then
                        fetch_line <= to_integer(line_fetch_shadow);
                        fetch_word_cnt <= 0;
                        fetch_burst_cnt <= 0;
                        fetch_buf_sel  <= line_fill_shadow;
                        fetch_state    <= F_REQ;
                    end if;

                when F_REQ =>
                    -- Issue burst read request
                    vga_rd_adr_o <= std_logic_vector(
                        fb_base +
                        to_unsigned(fetch_line * LINE_WORDS + fetch_word_cnt, 25)
                    );
                    vga_rd_req_o <= '1';
                    dbg_req_count <= dbg_req_count + 1;
                    fetch_burst_cnt <= 0;
                    fetch_state  <= F_POP;

                when F_POP =>
                    if vga_rd_valid_i = '1' then
                        dbg_valid_count <= dbg_valid_count + 1;
                        if fetch_word_cnt = LINE_WORDS - 1 then
                            fetch_state <= F_LINE_DONE;
                        else
                            fetch_word_cnt <= fetch_word_cnt + 1;
                            if fetch_burst_cnt = BURST_LEN - 1 then
                                dbg_burst_done_count <= dbg_burst_done_count + 1;
                                fetch_burst_cnt <= 0;
                                fetch_state <= F_NEXT_BURST;
                            else
                                fetch_burst_cnt <= fetch_burst_cnt + 1;
                            end if;
                        end if;
                    end if;

                when F_NEXT_BURST =>
                    if fetch_word_cnt >= LINE_WORDS then
                        fetch_state <= F_LINE_DONE;
                    else
                        fetch_state <= F_REQ;
                    end if;

                when F_LINE_DONE =>
                    fetch_state <= F_IDLE;
            end case;
        end if;
    end process;

end architecture rtl;
