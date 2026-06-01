-- fb_reader_rgb565.vhd -- framebuffer reader + line buffers for RGB565 scanout
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library altera_mf;
use altera_mf.altera_mf_components.all;

entity fb_reader_rgb565 is
    port (
        clk_50m_i       : in  std_logic;
        rst_n_i         : in  std_logic;
        clk_25m_i       : in  std_logic;
        mode_en_i       : in  std_logic;
        fb_base_i       : in  std_logic_vector(24 downto 0);
        active_x_i      : in  unsigned(9 downto 0);
        line_index_i    : in  unsigned(8 downto 0);
        video_on_i      : in  std_logic;
        line_start_i    : in  std_logic;
        pixel_color_o   : out std_logic_vector(15 downto 0);
        pixel_valid_o   : out std_logic;
        dbg_state_o     : out std_logic_vector(2 downto 0);
        dbg_fill_buf_o  : out std_logic;
        dbg_fetch_word_o : out std_logic_vector(11 downto 0);
        dbg_fetch_burst_o : out std_logic_vector(7 downto 0);
        dbg_fetch_line_o : out std_logic_vector(8 downto 0);
        dbg_next_line_o  : out std_logic_vector(8 downto 0);
        dbg_req_count_o  : out std_logic_vector(15 downto 0);
        dbg_valid_count_o : out std_logic_vector(15 downto 0);
        dbg_line_evt_count_o : out std_logic_vector(15 downto 0);
        dbg_burst_done_count_o : out std_logic_vector(15 downto 0);
        sample_disp_word_o : out std_logic_vector(31 downto 0);
        sample_linebuf_a_o : out std_logic_vector(31 downto 0);
        sample_linebuf_b_o : out std_logic_vector(31 downto 0);
        rd_addr_o      : out std_logic_vector(8 downto 0);
        wr_addr_o      : out std_logic_vector(8 downto 0);
        linebuf_a_wren_o : out std_logic;
        linebuf_b_wren_o : out std_logic;
        vga_rd_adr_o   : out std_logic_vector(24 downto 0);
        vga_rd_req_o   : out std_logic;
        vga_rd_data_i  : in  std_logic_vector(31 downto 0);
        vga_rd_valid_i : in  std_logic;
        vga_rd_done_i  : in  std_logic
    );
end entity fb_reader_rgb565;

architecture rtl of fb_reader_rgb565 is

    constant LINE_WORDS : integer := 320;
    constant V_ACTIVE   : integer := 480;
    constant BURST_LEN  : integer := 8;

    signal fb_base : unsigned(24 downto 0);

    signal linebuf_wr_addr : std_logic_vector(8 downto 0);
    signal linebuf_rd_addr : std_logic_vector(8 downto 0);
    signal linebuf_wr_data : std_logic_vector(31 downto 0);
    signal linebuf_a_q     : std_logic_vector(31 downto 0);
    signal linebuf_b_q     : std_logic_vector(31 downto 0);
    signal linebuf_a_wren  : std_logic;
    signal linebuf_b_wren  : std_logic;

    signal buf_sel         : std_logic;
    signal disp_word_q     : std_logic_vector(31 downto 0);
    signal active_x_q      : unsigned(9 downto 0);
    signal active_x_d      : unsigned(9 downto 0);
    signal buf_sel_q       : std_logic;
    signal fb_video_q      : std_logic;
    signal fb_video_d      : std_logic;
    signal pixel_color     : std_logic_vector(15 downto 0);

    type fetch_state_t is (F_IDLE, F_REQ, F_POP, F_NEXT_BURST, F_LINE_DONE);
    signal fetch_state      : fetch_state_t;
    signal fetch_line       : integer range 0 to V_ACTIVE + 1;
    signal fetch_word_cnt   : integer range 0 to LINE_WORDS - 1;
    signal fetch_burst_cnt  : integer range 0 to BURST_LEN - 1;
    signal fetch_buf_sel    : std_logic;

    signal line_req_toggle_25m : std_logic;
    signal line_req_toggle_sync : std_logic_vector(2 downto 0);
    signal line_req_seen_50m : std_logic;
    signal line_req_fire_50m : std_logic;
    signal line_fetch_shadow : unsigned(8 downto 0);
    signal line_fill_shadow  : std_logic;

    signal dbg_req_count        : unsigned(15 downto 0);
    signal dbg_valid_count      : unsigned(15 downto 0);
    signal dbg_line_evt_count   : unsigned(15 downto 0);
    signal dbg_burst_done_count : unsigned(15 downto 0);

begin

    fb_base <= unsigned(fb_base_i);
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
        widthad_a              => 9,
        numwords_a             => 320,
        width_b                => 32,
        widthad_b              => 9,
        numwords_b             => 320,
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
        clock1    => clk_25m_i,
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
        widthad_a              => 9,
        numwords_a             => 320,
        width_b                => 32,
        widthad_b              => 9,
        numwords_b             => 320,
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
        clock1    => clk_25m_i,
        address_a => linebuf_wr_addr,
        address_b => linebuf_rd_addr,
        data_a    => linebuf_wr_data,
        wren_a    => linebuf_b_wren,
        q_b       => linebuf_b_q
    );

    p_bufswap : process(clk_25m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            buf_sel <= '0';
            line_req_toggle_25m <= '0';
            line_fetch_shadow <= (others => '0');
            line_fill_shadow <= '0';
        elsif rising_edge(clk_25m_i) then
            if line_start_i = '1' then
                -- active_y_i is only valid during video_on. line_start_i occurs in the
                -- horizontal blanking interval, so use an explicit visible-line index.
                if line_index_i < to_unsigned(V_ACTIVE - 1, line_index_i'length) then
                    line_fetch_shadow <= resize(line_index_i, line_fetch_shadow'length) + 1;
                else
                    line_fetch_shadow <= (others => '0');
                end if;
                line_fill_shadow <= buf_sel;
                line_req_toggle_25m <= not line_req_toggle_25m;
                buf_sel <= not buf_sel;
            end if;
        end if;
    end process;

    p_rd_addr : process(all)
    begin
        linebuf_rd_addr <= (others => '0');
        if video_on_i = '1' then
            linebuf_rd_addr <= std_logic_vector(active_x_i(9 downto 1));
        end if;
    end process;

    p_rd_pipe : process(clk_25m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            active_x_q  <= (others => '0');
            active_x_d  <= (others => '0');
            disp_word_q <= (others => '0');
            buf_sel_q   <= '0';
            fb_video_q  <= '0';
            fb_video_d  <= '0';
        elsif rising_edge(clk_25m_i) then
            if fb_video_q = '1' then
                active_x_d <= active_x_q;
                if buf_sel_q = '0' then
                    disp_word_q <= linebuf_a_q;
                else
                    disp_word_q <= linebuf_b_q;
                end if;
            else
                active_x_d <= (others => '0');
                disp_word_q <= (others => '0');
            end if;

            if video_on_i = '1' then
                active_x_q <= active_x_i;
            else
                active_x_q <= (others => '0');
            end if;

            buf_sel_q  <= buf_sel;
            fb_video_q <= video_on_i and mode_en_i;
            fb_video_d <= fb_video_q;
        end if;
    end process;

    p_pixel : process(clk_25m_i, rst_n_i)
        variable next_color : std_logic_vector(15 downto 0);
    begin
        if rst_n_i = '0' then
            pixel_color <= (others => '0');
        elsif rising_edge(clk_25m_i) then
            next_color := (others => '0');
            if fb_video_d = '1' then
                if active_x_d(0) = '0' then
                    next_color := disp_word_q(15 downto 0);
                else
                    next_color := disp_word_q(31 downto 16);
                end if;
            end if;
            pixel_color <= next_color;
        end if;
    end process;

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

    p_fetch : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            fetch_state <= F_IDLE;
            fetch_line <= 0;
            fetch_word_cnt <= 0;
            fetch_burst_cnt <= 0;
            fetch_buf_sel <= '0';
            vga_rd_req_o <= '0';
            vga_rd_adr_o <= (others => '0');
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
                    if line_req_fire_50m = '1' and mode_en_i = '1' then
                        fetch_line <= to_integer(line_fetch_shadow);
                        fetch_word_cnt <= 0;
                        fetch_burst_cnt <= 0;
                        fetch_buf_sel <= line_fill_shadow;
                        fetch_state <= F_REQ;
                    end if;

                when F_REQ =>
                    vga_rd_adr_o <= std_logic_vector(
                        fb_base + to_unsigned(fetch_line * LINE_WORDS + fetch_word_cnt, 25)
                    );
                    vga_rd_req_o <= '1';
                    dbg_req_count <= dbg_req_count + 1;
                    fetch_burst_cnt <= 0;
                    fetch_state <= F_POP;

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
                    fetch_state <= F_REQ;

                when F_LINE_DONE =>
                    fetch_state <= F_IDLE;
            end case;
        end if;
    end process;

    with fetch_state select dbg_state_o <=
        "000" when F_IDLE,
        "001" when F_REQ,
        "010" when F_POP,
        "011" when F_NEXT_BURST,
        "100" when others;

    pixel_color_o <= pixel_color;
    pixel_valid_o <= fb_video_d;
    dbg_fill_buf_o <= line_fill_shadow;
    dbg_fetch_word_o <= std_logic_vector(to_unsigned(fetch_word_cnt, dbg_fetch_word_o'length));
    dbg_fetch_burst_o <= std_logic_vector(to_unsigned(fetch_burst_cnt, dbg_fetch_burst_o'length));
    dbg_fetch_line_o <= std_logic_vector(to_unsigned(fetch_line, dbg_fetch_line_o'length));
    dbg_next_line_o <= std_logic_vector(line_fetch_shadow);
    dbg_req_count_o <= std_logic_vector(dbg_req_count);
    dbg_valid_count_o <= std_logic_vector(dbg_valid_count);
    dbg_line_evt_count_o <= std_logic_vector(dbg_line_evt_count);
    dbg_burst_done_count_o <= std_logic_vector(dbg_burst_done_count);
    sample_disp_word_o <= disp_word_q;
    sample_linebuf_a_o <= linebuf_a_q;
    sample_linebuf_b_o <= linebuf_b_q;
    rd_addr_o <= linebuf_rd_addr;
    wr_addr_o <= linebuf_wr_addr;
    linebuf_a_wren_o <= linebuf_a_wren;
    linebuf_b_wren_o <= linebuf_b_wren;

end architecture rtl;
