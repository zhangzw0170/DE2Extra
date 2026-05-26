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
--
-- SDRAM interface: VGA burst-read port on sdram_ctrl.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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

    -- Line buffers: 160 x 32-bit, one word = 4 RGB332 pixels
    type linebuf_t is array(0 to LINE_WORDS - 1) of std_logic_vector(31 downto 0);
    signal linebuf_a : linebuf_t := (others => (others => '0'));
    signal linebuf_b : linebuf_t := (others => (others => '0'));
    attribute ramstyle : string;
    attribute ramstyle of linebuf_a : signal is "M9K";
    attribute ramstyle of linebuf_b : signal is "M9K";

    -- Ping-pong: '0' → A = display, B = fill; '1' → B = display, A = fill
    signal buf_sel : std_logic;

    -- Pixel output shift register (25 MHz domain)
    signal px_shift : std_logic_vector(31 downto 0);
    signal px_phase : integer range 0 to 3;  -- which pixel in current word
    signal px_word_addr : integer range 0 to LINE_WORDS - 1;

    -- Pipeline register for pixel color → DAC
    signal pixel_color : std_logic_vector(7 downto 0);

    -- SDRAM fetch FSM (50 MHz domain)
    type fetch_state_t is (F_IDLE, F_REQ, F_POP, F_NEXT_BURST, F_LINE_DONE);
    signal fetch_state    : fetch_state_t;
    signal fetch_line     : integer range 0 to V_ACTIVE + 1;  -- can go past V_ACTIVE briefly
    signal fetch_word_cnt : integer range 0 to LINE_WORDS - 1;
    signal fetch_buf_sel  : std_logic;

    -- Synchronized VGA timing from 25 MHz → 50 MHz domain
    signal v_count_sync : integer range 0 to V_TOTAL - 1;
    signal v_count_d1   : integer range 0 to V_TOTAL - 1;
    signal new_line_pulse : std_logic;
    signal buf_sel_meta   : std_logic;
    signal buf_sel_sync   : std_logic;

    -- Register ack
    signal reg_ack_ff : std_logic;

begin

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

    p_reg_rd : process(reg_adr_i, mode_en, fb_base, video_on)
        variable adr : integer;
    begin
        reg_dat_o <= (others => '0');
        adr := to_integer(unsigned(reg_adr_i(15 downto 2)));
        case adr is
            when 0 =>
                reg_dat_o(0) <= mode_en;
                reg_dat_o(1) <= testpat_en;
            when 1 => reg_dat_o(26 downto 2) <= std_logic_vector(fb_base);
            when 2 => reg_dat_o(0) <= not video_on;
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
    begin
        if rst_n_i = '0' then
            buf_sel <= '0';
        elsif rising_edge(clk_25m) then
            if h_count = 0 and v_count >= (V_SYNC + V_BP) and v_count < (V_SYNC + V_BP + V_ACTIVE) then
                buf_sel <= not buf_sel;
            end if;
        end if;
    end process;

    -- ================================================================
    -- Pixel output: read line buffer, shift out 4 pixels per word
    -- (25 MHz domain)
    -- ================================================================
    p_pixel_out : process(clk_25m, rst_n_i)
        variable word_idx : integer range 0 to LINE_WORDS - 1;
        variable pat_color : std_logic_vector(7 downto 0);
        variable px_vis    : integer range 0 to H_ACTIVE - 1;
        variable py_vis    : integer range 0 to V_ACTIVE - 1;
    begin
        if rst_n_i = '0' then
            px_shift     <= (others => '0');
            px_phase     <= 0;
            px_word_addr <= 0;
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

                px_phase     <= 0;
                px_word_addr <= 0;
                px_shift     <= (others => '0');
                pixel_color  <= pat_color;
            elsif video_on = '1' and mode_en = '1' then
                -- Shift register: load new word every 4 pixels
                if px_phase = 0 then
                    px_word_addr <= px_word_addr;
                    word_idx := px_word_addr;
                    if buf_sel = '0' then
                        px_shift <= linebuf_a(word_idx);
                    else
                        px_shift <= linebuf_b(word_idx);
                    end if;
                else
                    px_shift <= px_shift(23 downto 0) & x"00";
                end if;

                -- Extract current pixel (MSB-first: pixel 0 = bits 31:24)
                pixel_color <= px_shift(31 downto 24);

                -- Advance phase
                if px_phase = 3 then
                    px_phase <= 0;
                    if px_word_addr = LINE_WORDS - 1 then
                        px_word_addr <= 0;
                    else
                        px_word_addr <= px_word_addr + 1;
                    end if;
                else
                    px_phase <= px_phase + 1;
                end if;
            else
                -- During blanking or disabled, reset counters
                if h_count = (H_SYNC + H_BP + H_ACTIVE) then
                    -- Just left the active display area: reset for next visible line
                    px_phase     <= 0;
                    px_word_addr <= 0;
                end if;
                pixel_color <= (others => '0');
            end if;

            -- RGB332 → RGB888 expansion (1 pipeline stage)
            vga_r_o <= pixel_color(7 downto 5) & pixel_color(7 downto 5) & pixel_color(6) & pixel_color(5);
            vga_g_o <= pixel_color(4 downto 2) & pixel_color(4 downto 2) & pixel_color(3) & pixel_color(2);
            vga_b_o <= pixel_color(1 downto 0) & pixel_color(1 downto 0) &
                       pixel_color(1 downto 0) & pixel_color(1) & pixel_color(0);
        end if;
    end process;

    -- ================================================================
    -- Synchronize VGA v_count from 25 MHz → 50 MHz for fetch trigger
    -- ================================================================
    p_sync_vcount : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            v_count_sync <= 0;
            v_count_d1   <= 0;
            new_line_pulse <= '0';
        elsif rising_edge(clk_50m_i) then
            v_count_d1 <= v_count_sync;
            v_count_sync <= v_count;  -- direct cross-domain read (safe: gray-code or slow-changing)
            if v_count_sync /= v_count_d1 then
                new_line_pulse <= '1';
            else
                new_line_pulse <= '0';
            end if;
        end if;
    end process;

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
            fetch_buf_sel  <= '0';
            vga_rd_req_o   <= '0';
            vga_rd_adr_o   <= (others => '0');
            buf_sel_meta   <= '0';
            buf_sel_sync   <= '0';
        elsif rising_edge(clk_50m_i) then
            vga_rd_req_o <= '0';
            buf_sel_meta <= buf_sel;
            buf_sel_sync <= buf_sel_meta;

            case fetch_state is
                when F_IDLE =>
                    if new_line_pulse = '1' and mode_en = '1'
                       and v_count_sync >= (V_SYNC + V_BP)
                       and v_count_sync < (V_SYNC + V_BP + V_ACTIVE) then
                        -- Fetch the scanline that will be displayed next
                        -- Current display line = v_count_sync - visible top margin
                        -- Next line to fill = v_count_sync + 1 (or 0 if wrapping)
                        if (v_count_sync - (V_SYNC + V_BP)) < V_ACTIVE - 1 then
                            fetch_line <= (v_count_sync - (V_SYNC + V_BP)) + 1;
                        else
                            fetch_line <= 0;
                        end if;
                        fetch_word_cnt <= 0;
                        fetch_buf_sel  <= not buf_sel_sync;
                        fetch_state    <= F_REQ;
                    end if;

                when F_REQ =>
                    -- Issue burst read request
                    vga_rd_adr_o <= std_logic_vector(
                        fb_base +
                        to_unsigned(fetch_line * LINE_WORDS + fetch_word_cnt, 25)
                    );
                    vga_rd_req_o <= '1';
                    fetch_state  <= F_POP;

                when F_POP =>
                    if vga_rd_valid_i = '1' then
                        -- Write one word into fill buffer
                        if fetch_buf_sel = '0' then
                            linebuf_a(fetch_word_cnt) <= vga_rd_data_i;
                        else
                            linebuf_b(fetch_word_cnt) <= vga_rd_data_i;
                        end if;

                        if fetch_word_cnt = LINE_WORDS - 1 then
                            fetch_state <= F_LINE_DONE;
                        else
                            fetch_word_cnt <= fetch_word_cnt + 1;
                            if vga_rd_done_i = '1' then
                                fetch_state <= F_NEXT_BURST;
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
