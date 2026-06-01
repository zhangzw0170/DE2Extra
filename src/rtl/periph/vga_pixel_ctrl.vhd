-- vga_pixel_ctrl.vhd -- pixel-mode VGA wrapper (registers + scanout composition)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_pixel_ctrl is
    port (
        clk_50m_i   : in  std_logic;
        rst_n_i     : in  std_logic;
        clk_25m_i   : in  std_logic;

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

        -- SDRAM burst read request -> sdram_ctrl VGA port
        vga_rd_adr_o   : out std_logic_vector(24 downto 0);
        vga_rd_req_o   : out std_logic;
        vga_rd_data_i  : in  std_logic_vector(31 downto 0);
        vga_rd_valid_i : in  std_logic;
        vga_rd_done_i  : in  std_logic
    );
end entity vga_pixel_ctrl;

architecture rtl of vga_pixel_ctrl is

    constant H_ACTIVE : integer := 640;
    constant V_ACTIVE : integer := 480;

    signal mode_en    : std_logic;
    signal testpat_en : std_logic;
    signal fb_base    : unsigned(24 downto 0);
    signal reg_ack_ff : std_logic;

    signal h_count    : unsigned(9 downto 0);
    signal v_count    : unsigned(9 downto 0);
    signal active_x   : unsigned(9 downto 0);
    signal active_y   : unsigned(8 downto 0);
    signal line_index : unsigned(8 downto 0);
    signal video_on   : std_logic;
    signal line_start : std_logic;
    signal int_hs     : std_logic;
    signal int_vs     : std_logic;
    signal int_blank  : std_logic;
    signal int_sync   : std_logic;

    signal fb_pixel_color : std_logic_vector(15 downto 0);
    signal fb_pixel_valid : std_logic;

    signal dbg_state        : std_logic_vector(2 downto 0);
    signal dbg_fill_buf     : std_logic;
    signal dbg_fetch_word   : std_logic_vector(11 downto 0);
    signal dbg_fetch_burst  : std_logic_vector(7 downto 0);
    signal dbg_fetch_line   : std_logic_vector(8 downto 0);
    signal dbg_next_line    : std_logic_vector(8 downto 0);
    signal dbg_req_count    : std_logic_vector(15 downto 0);
    signal dbg_valid_count  : std_logic_vector(15 downto 0);
    signal dbg_line_evt_count : std_logic_vector(15 downto 0);
    signal dbg_burst_done_count : std_logic_vector(15 downto 0);
    signal sample_disp_word : std_logic_vector(31 downto 0);
    signal sample_linebuf_a : std_logic_vector(31 downto 0);
    signal sample_linebuf_b : std_logic_vector(31 downto 0);
    signal rd_addr          : std_logic_vector(8 downto 0);
    signal wr_addr          : std_logic_vector(8 downto 0);
    signal linebuf_a_wren   : std_logic;
    signal linebuf_b_wren   : std_logic;

    signal pixel_color      : std_logic_vector(15 downto 0);
    signal pixel_r          : std_logic_vector(7 downto 0);
    signal pixel_g          : std_logic_vector(7 downto 0);
    signal pixel_b          : std_logic_vector(7 downto 0);

begin

    u_timing : entity work.vga_timing_640x480
    port map (
        clk_25m_i    => clk_25m_i,
        rst_n_i      => rst_n_i,
        h_count_o    => h_count,
        v_count_o    => v_count,
        active_x_o   => active_x,
        active_y_o   => active_y,
        line_index_o => line_index,
        video_on_o   => video_on,
        line_start_o => line_start,
        hs_o         => int_hs,
        vs_o         => int_vs,
        blank_o      => int_blank,
        sync_o       => int_sync
    );

    u_fb_reader : entity work.fb_reader_rgb565
    port map (
        clk_50m_i       => clk_50m_i,
        rst_n_i         => rst_n_i,
        clk_25m_i       => clk_25m_i,
        mode_en_i       => mode_en,
        fb_base_i       => std_logic_vector(fb_base),
        active_x_i      => active_x,
        line_index_i    => line_index,
        video_on_i      => video_on,
        line_start_i    => line_start,
        pixel_color_o   => fb_pixel_color,
        pixel_valid_o   => fb_pixel_valid,
        dbg_state_o     => dbg_state,
        dbg_fill_buf_o  => dbg_fill_buf,
        dbg_fetch_word_o => dbg_fetch_word,
        dbg_fetch_burst_o => dbg_fetch_burst,
        dbg_fetch_line_o => dbg_fetch_line,
        dbg_next_line_o  => dbg_next_line,
        dbg_req_count_o  => dbg_req_count,
        dbg_valid_count_o => dbg_valid_count,
        dbg_line_evt_count_o => dbg_line_evt_count,
        dbg_burst_done_count_o => dbg_burst_done_count,
        sample_disp_word_o => sample_disp_word,
        sample_linebuf_a_o => sample_linebuf_a,
        sample_linebuf_b_o => sample_linebuf_b,
        rd_addr_o      => rd_addr,
        wr_addr_o      => wr_addr,
        linebuf_a_wren_o => linebuf_a_wren,
        linebuf_b_wren_o => linebuf_b_wren,
        vga_rd_adr_o   => vga_rd_adr_o,
        vga_rd_req_o   => vga_rd_req_o,
        vga_rd_data_i  => vga_rd_data_i,
        vga_rd_valid_i => vga_rd_valid_i,
        vga_rd_done_i  => vga_rd_done_i
    );

    vga_clk_o <= clk_25m_i;

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
                        when 1 =>
                            fb_base <= unsigned(reg_dat_i(26 downto 2));
                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    reg_ack_o <= reg_ack_ff;
    mode_en_o <= mode_en;

    p_reg_rd : process(reg_adr_i, mode_en, testpat_en, fb_base, video_on,
                       dbg_state, dbg_fill_buf, dbg_fetch_burst, dbg_fetch_word,
                       dbg_fetch_line, dbg_next_line, dbg_req_count,
                       dbg_valid_count, dbg_line_evt_count, dbg_burst_done_count,
                       sample_disp_word, sample_linebuf_a, sample_linebuf_b,
                       rd_addr, wr_addr, linebuf_a_wren, linebuf_b_wren)
        variable adr : integer;
    begin
        reg_dat_o <= (others => '0');
        adr := to_integer(unsigned(reg_adr_i(15 downto 2)));
        case adr is
            when 0 =>
                reg_dat_o(0) <= mode_en;
                reg_dat_o(1) <= testpat_en;
            when 1 =>
                reg_dat_o(26 downto 2) <= std_logic_vector(fb_base);
            when 2 =>
                reg_dat_o(0) <= not video_on;
            when 3 =>
                reg_dat_o(2 downto 0)   <= dbg_state;
                reg_dat_o(3)            <= dbg_fill_buf;
                reg_dat_o(11 downto 4)  <= dbg_fetch_burst;
                reg_dat_o(23 downto 12) <= dbg_fetch_word;
            when 4 =>
                reg_dat_o(8 downto 0)   <= dbg_fetch_line;
                reg_dat_o(17 downto 9)  <= dbg_next_line;
            when 5 =>
                reg_dat_o(15 downto 0)  <= dbg_req_count;
                reg_dat_o(31 downto 16) <= dbg_valid_count;
            when 6 =>
                reg_dat_o(15 downto 0)  <= dbg_line_evt_count;
                reg_dat_o(31 downto 16) <= dbg_burst_done_count;
            when 7 =>
                reg_dat_o <= sample_disp_word;
            when 8 =>
                reg_dat_o <= sample_linebuf_a;
            when 9 =>
                reg_dat_o <= sample_linebuf_b;
            when 10 =>
                reg_dat_o(8 downto 0) <= rd_addr;
                reg_dat_o(17 downto 9) <= wr_addr;
                reg_dat_o(16) <= linebuf_a_wren;
                reg_dat_o(17) <= linebuf_b_wren;
            when others =>
                null;
        end case;
    end process;

    p_pixel_select : process(clk_25m_i, rst_n_i)
        variable pat_color : std_logic_vector(15 downto 0);
        variable sel_color : std_logic_vector(15 downto 0);
    begin
        if rst_n_i = '0' then
            pixel_color <= (others => '0');
            pixel_r     <= (others => '0');
            pixel_g     <= (others => '0');
            pixel_b     <= (others => '0');
        elsif rising_edge(clk_25m_i) then
            pat_color := (others => '0');
            sel_color := (others => '0');

            if video_on = '1' and mode_en = '1' and testpat_en = '1' then
                if active_y < to_unsigned(96, active_y'length) then
                    case to_integer(active_x) / 80 is
                        when 0 => pat_color := x"F800";
                        when 1 => pat_color := x"FFE0";
                        when 2 => pat_color := x"07E0";
                        when 3 => pat_color := x"07FF";
                        when 4 => pat_color := x"001F";
                        when 5 => pat_color := x"F81F";
                        when 6 => pat_color := x"FD20";
                        when others => pat_color := x"FFFF";
                    end case;
                elsif (active_x < to_unsigned(8, active_x'length)) or
                      (active_x >= to_unsigned(H_ACTIVE - 8, active_x'length)) or
                      (active_y < to_unsigned(8, active_y'length)) or
                      (active_y >= to_unsigned(V_ACTIVE - 8, active_y'length)) then
                    pat_color := x"FFFF";
                elsif ((to_integer(active_x) / 32) mod 2) = ((to_integer(active_y) / 32) mod 2) then
                    pat_color := x"1084";
                else
                    pat_color := x"0000";
                end if;
                sel_color := pat_color;
            elsif fb_pixel_valid = '1' then
                sel_color := fb_pixel_color;
            end if;

            pixel_color <= sel_color;
            pixel_r <= sel_color(15 downto 11) & sel_color(15 downto 13);
            pixel_g <= sel_color(10 downto 5)  & sel_color(10 downto 9);
            pixel_b <= sel_color(4 downto 0)   & sel_color(4 downto 2);
        end if;
    end process;

    p_output_reg : process(clk_25m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            vga_r_o     <= (others => '0');
            vga_g_o     <= (others => '0');
            vga_b_o     <= (others => '0');
            vga_hs_o    <= '1';
            vga_vs_o    <= '1';
            vga_blank_o <= '0';
            vga_sync_o  <= '1';
        elsif falling_edge(clk_25m_i) then
            vga_r_o     <= pixel_r;
            vga_g_o     <= pixel_g;
            vga_b_o     <= pixel_b;
            vga_hs_o    <= int_hs;
            vga_vs_o    <= int_vs;
            vga_blank_o <= int_blank;
            vga_sync_o  <= int_sync;
        end if;
    end process;

end architecture rtl;
