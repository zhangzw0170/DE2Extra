-- vga_text_terminal.vhd -- VGA 80x30 text terminal (640x480 @ 60Hz, RGB565)
--
-- 32-bit cell: [31:24]=ASCII, [23:16]=reserved, [15:0]=fg RGB565
-- Background color from global bg_color register (not per-cell)
-- Dual-port M9K BRAM (4096x32): Port A 50MHz CPU write, Port B 25MHz render read
-- Font ROM: font_rom_pkg CP437, 256 chars x 16 rows, 8-bit wide

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.font_rom_pkg.all;

entity vga_text_terminal is
    port (
        clk_50m_i   : in  std_logic;
        rst_n_i     : in  std_logic;

        -- VGA output (24-bit, 8-8-8 from RGB565 expansion)
        vga_r_o     : out std_logic_vector(7 downto 0);
        vga_g_o     : out std_logic_vector(7 downto 0);
        vga_b_o     : out std_logic_vector(7 downto 0);
        vga_hs_o    : out std_logic;
        vga_vs_o    : out std_logic;
        vga_blank_o : out std_logic;
        vga_sync_o  : out std_logic;
        vga_clk_o   : out std_logic;

        -- Register interface (Wishbone, 32-bit data)
        reg_adr_i   : in  std_logic_vector(15 downto 0);
        reg_dat_i   : in  std_logic_vector(31 downto 0);
        reg_dat_o   : out std_logic_vector(31 downto 0);
        reg_we_i    : in  std_logic;
        reg_stb_i   : in  std_logic;
        reg_ack_o   : out std_logic;

        -- ChromaShader override (25MHz domain, aligned with bram_q)
        chroma_en_i    : in  std_logic := '0';
        chroma_char_i  : in  std_logic_vector(7 downto 0) := x"20";
        chroma_fg_i    : in  std_logic_vector(15 downto 0) := x"FFFF";
        chroma_bg_i    : in  std_logic_vector(15 downto 0) := x"0000";

        -- Exposed 25MHz clock and BRAM read address for ChromaShader
        clk_25m_o      : out std_logic;
        brm_rd_addr_o  : out integer range 0 to 2399
    );
end entity vga_text_terminal;

architecture rtl of vga_text_terminal is

    -- VGA 640x480 @ 60Hz timing (800x525 total)
    constant H_TOTAL  : integer := 800;
    constant H_SYNC   : integer := 96;
    constant H_BP     : integer := 48;
    constant H_ACTIVE : integer := 640;
    constant V_TOTAL  : integer := 525;
    constant V_SYNC   : integer := 2;
    constant V_BP     : integer := 33;
    constant V_ACTIVE : integer := 480;

    -- Text grid
    constant COLS     : integer := 80;
    constant ROWS     : integer := 30;
    constant CHAR_W   : integer := 8;
    constant CHAR_H   : integer := 16;
    constant BUF_SIZE : integer := 2400;
    constant RAM_DEPTH : integer := 4096;  -- single visible page fits without growing BRAM
    constant REG_BASE    : integer := BUF_SIZE * 4;
    constant REG_CURSOR_X : integer := REG_BASE + 16#00#;
    constant REG_CURSOR_Y : integer := REG_BASE + 16#04#;
    constant REG_CONTROL  : integer := REG_BASE + 16#08#;
    constant REG_STATUS   : integer := REG_BASE + 16#0C#;
    constant REG_BGCOLOR  : integer := REG_BASE + 16#10#;
    constant REG_CLEAR    : integer := REG_BASE + 16#14#;

    constant BLINK_MAX : integer := 25_000_000;  -- 0.5s @ 50MHz

    -- 25MHz pixel clock (toggle on 50MHz)
    signal clk_25m      : std_logic := '0';

    -- VGA timing counters
    signal h_count      : integer range 0 to H_TOTAL - 1 := 0;
    signal v_count      : integer range 0 to V_TOTAL - 1 := 0;
    signal video_on     : std_logic;
    signal pixel_x      : integer range 0 to H_ACTIVE - 1 := 0;
    signal pixel_y      : integer range 0 to V_ACTIVE - 1 := 0;

    -- Text buffer BRAM (dual-port, inferred M9K)
    type ram_t is array (0 to RAM_DEPTH - 1) of std_logic_vector(31 downto 0);
    signal char_ram     : ram_t := (others => x"00200000");
    attribute ramstyle  : string;
    attribute ramstyle of char_ram : signal is "M9K, no_rw_check";

    -- BRAM port B read pipeline (25MHz domain)
    signal bram_rd_addr : integer range 0 to RAM_DEPTH - 1 := 0;
    signal bram_q       : std_logic_vector(31 downto 0) := (others => '0');
    signal sub_row      : integer range 0 to CHAR_H - 1;

    -- Registered pixel coordinates (aligned with bram_q, 1-cycle delayed)
    signal px_d         : integer range 0 to H_ACTIVE - 1 := 0;
    signal py_d         : integer range 0 to V_ACTIVE - 1 := 0;
    signal sub_row_d    : integer range 0 to CHAR_H - 1 := 0;

    -- Cursor / control registers (50MHz domain, read by 25MHz)
    signal cursor_x     : integer range 0 to COLS - 1 := 0;
    signal cursor_y     : integer range 0 to ROWS - 1 := 0;
    signal ctrl_enable  : std_logic := '1';
    signal ctrl_blink   : std_logic := '1';
    signal ctrl_page    : std_logic := '0';
    signal bg_color     : std_logic_vector(15 downto 0) := x"0000";  -- RGB565

    -- Blink counter (25MHz)
    signal blink_cnt    : integer range 0 to BLINK_MAX - 1 := 0;
    signal blink_vis    : std_logic := '1';

    -- Register interface (50MHz)
    signal reg_ack      : std_logic := '0';

    -- Clear screen state machine
    signal clr_active   : std_logic := '0';
    signal clr_addr     : integer range 0 to BUF_SIZE - 1 := 0;

begin

    ----------------------------------------------------------------
    -- 25MHz pixel clock
    ----------------------------------------------------------------
    process(clk_50m_i)
    begin
        if rising_edge(clk_50m_i) then
            clk_25m <= not clk_25m;
        end if;
    end process;
    vga_clk_o <= clk_25m;
    clk_25m_o <= clk_25m;

    ----------------------------------------------------------------
    -- VGA timing (25MHz)
    ----------------------------------------------------------------
    process(clk_25m)
    begin
        if rising_edge(clk_25m) then
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

    pixel_x <= h_count - (H_SYNC + H_BP) when video_on = '1' else 0;
    pixel_y <= v_count - (V_SYNC + V_BP) when video_on = '1' else 0;

    vga_hs_o   <= '1' when h_count >= H_SYNC else '0';
    vga_vs_o   <= '1' when v_count >= V_SYNC else '0';
    vga_blank_o <= video_on;
    -- Match the known-good Exp6/Exp7 behaviour on DE2-115:
    -- keep composite sync inactive during active video to avoid sync-on-green bias.
    vga_sync_o <= '0' when (h_count >= H_SYNC and v_count >= V_SYNC) else '1';

    ----------------------------------------------------------------
    -- Blink counter (25MHz)
    ----------------------------------------------------------------
    process(clk_25m)
    begin
        if rising_edge(clk_25m) then
            if blink_cnt = BLINK_MAX - 1 then
                blink_cnt <= 0;
                blink_vis <= not blink_vis;
            else
                blink_cnt <= blink_cnt + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- BRAM read address (25MHz, combinational)
    ----------------------------------------------------------------
    process(all)
        variable char_col : integer range 0 to COLS - 1;
        variable char_row : integer range 0 to ROWS - 1;
    begin
        char_col := pixel_x / CHAR_W;
        if pixel_y / CHAR_H >= ROWS then
            char_row := ROWS - 1;  -- clamp: bottom margin pixels
        else
            char_row := pixel_y / CHAR_H;
        end if;
        bram_rd_addr <= char_row * COLS + char_col;
        sub_row     <= pixel_y mod CHAR_H;
        brm_rd_addr_o <= char_row * COLS + char_col;
    end process;

    ----------------------------------------------------------------
    -- BRAM read + coordinate register stage (25MHz)
    -- Registers bram_q, px_d, py_d, sub_row_d all on the same edge
    -- so they are aligned for the rendering stage.
    ----------------------------------------------------------------
    process(clk_25m)
    begin
        if rising_edge(clk_25m) then
            bram_q    <= char_ram(bram_rd_addr);
            px_d      <= pixel_x;
            py_d      <= pixel_y;
            sub_row_d <= sub_row;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Font ROM lookup + pixel rendering (25MHz, registered output)
    -- All inputs (bram_q, px_d, py_d, sub_row_d) are aligned.
    ----------------------------------------------------------------
    process(clk_25m)
        variable ascii_char : integer range 0 to 255;
        variable font_byte  : std_logic_vector(7 downto 0);
        variable pixel_bit  : std_logic;
        variable fg_rgb     : std_logic_vector(15 downto 0);
        variable bg_rgb     : std_logic_vector(15 downto 0);
        variable color_rgb  : std_logic_vector(15 downto 0);
        variable cursor_at  : std_logic;
    begin
        if rising_edge(clk_25m) then
            -- ChromaShader override: replace char/fg/bg when active
            if chroma_en_i = '1' then
                ascii_char := to_integer(unsigned(chroma_char_i));
                fg_rgb := chroma_fg_i;
                bg_rgb := chroma_bg_i;
            else
                ascii_char := to_integer(unsigned(bram_q(31 downto 24)));
                fg_rgb := bram_q(15 downto 0);
                bg_rgb := bg_color;
            end if;

            -- Font ROM: use variable for immediate use in this process
            font_byte := font_rom_data(ascii_char * 16 + sub_row_d);

            -- Pixel on: select bit from font data (MSB = leftmost pixel)
            pixel_bit := font_byte(7 - (px_d mod CHAR_W));

            -- Cursor detection (full character cell)
            -- Suppress cursor in chroma region
            cursor_at := '0';
            if ctrl_enable = '1' and chroma_en_i = '0' then
                if py_d >= (cursor_y * CHAR_H) and py_d < ((cursor_y + 1) * CHAR_H) then
                    if px_d >= (cursor_x * CHAR_W) and px_d < ((cursor_x + 1) * CHAR_W) then
                        cursor_at := '1';
                    end if;
                end if;
            end if;

            if pixel_bit = '1' then
                color_rgb := fg_rgb;
            else
                color_rgb := bg_rgb;
            end if;

            -- Cursor should remain visible even on a space glyph or black text cell.
            if cursor_at = '1' and (ctrl_blink = '0' or blink_vis = '1') then
                color_rgb := not color_rgb;
            end if;

            -- RGB565 to 8-bit expansion
            if video_on = '0' then
                vga_r_o <= x"00";
                vga_g_o <= x"00";
                vga_b_o <= x"00";
            else
                vga_r_o <= color_rgb(15 downto 11) & "000";
                vga_g_o <= color_rgb(10 downto 5)  & "00";
                vga_b_o <= color_rgb(4 downto 0)   & "000";
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Register interface + clear-screen FSM (50MHz)
    ----------------------------------------------------------------
    process(clk_50m_i)
        variable addr_int   : integer;
        variable next_cx    : integer;
        variable next_cy    : integer;
        variable word_addr  : integer;
    begin
        if rising_edge(clk_50m_i) then
            reg_ack   <= '0';
            reg_dat_o <= (others => '0');

            if clr_active = '1' then
                char_ram(clr_addr) <= x"00200000";  -- space, black fg
                if clr_addr = BUF_SIZE - 1 then
                    clr_active <= '0';
                else
                    clr_addr <= clr_addr + 1;
                end if;
                -- Acknowledge reads during clear (avoid XBUS timeout)
                if reg_stb_i = '1' and reg_we_i = '0' then
                    reg_ack <= '1';
                    addr_int := to_integer(unsigned(reg_adr_i));
                    if addr_int = REG_CURSOR_X then
                        reg_dat_o(6 downto 0) <= std_logic_vector(to_unsigned(cursor_x, 7));
                    elsif addr_int = REG_CURSOR_Y then
                        reg_dat_o(4 downto 0) <= std_logic_vector(to_unsigned(cursor_y, 5));
                    elsif addr_int = REG_CONTROL then
                        reg_dat_o <= (0 => ctrl_enable, 1 => ctrl_blink, 2 => ctrl_page, others => '0');
                    elsif addr_int = REG_BGCOLOR then
                        reg_dat_o <= x"0000" & bg_color;
                    end if;
                end if;
            elsif reg_stb_i = '1' then
                reg_ack <= '1';
                addr_int := to_integer(unsigned(reg_adr_i));

                if reg_we_i = '1' then
                    if addr_int < (BUF_SIZE * 4) then
                        word_addr := addr_int / 4;
                        if word_addr < RAM_DEPTH then
                            char_ram(word_addr) <= reg_dat_i;
                        end if;
                    elsif addr_int = REG_CURSOR_X then
                        next_cx := to_integer(unsigned(reg_dat_i(6 downto 0)));
                        if next_cx < COLS then
                            cursor_x <= next_cx;
                        end if;
                    elsif addr_int = REG_CURSOR_Y then
                        next_cy := to_integer(unsigned(reg_dat_i(4 downto 0)));
                        if next_cy < ROWS then
                            cursor_y <= next_cy;
                        end if;
                    elsif addr_int = REG_CONTROL then
                        ctrl_enable <= reg_dat_i(0);
                        ctrl_blink  <= reg_dat_i(1);
                        ctrl_page   <= reg_dat_i(2);
                    elsif addr_int = REG_BGCOLOR then
                        bg_color <= reg_dat_i(15 downto 0);
                    elsif addr_int = REG_CLEAR then
                        if reg_dat_i(0) = '1' then
                            clr_active <= '1';
                            clr_addr <= 0;
                        end if;
                    end if;
                else
                    if addr_int < (BUF_SIZE * 4) then
                        word_addr := addr_int / 4;
                        if word_addr < RAM_DEPTH then
                            reg_dat_o <= char_ram(word_addr);
                        end if;
                    elsif addr_int = REG_CURSOR_X then
                        reg_dat_o(6 downto 0) <= std_logic_vector(to_unsigned(cursor_x, 7));
                    elsif addr_int = REG_CURSOR_Y then
                        reg_dat_o(4 downto 0) <= std_logic_vector(to_unsigned(cursor_y, 5));
                    elsif addr_int = REG_CONTROL then
                        reg_dat_o <= (0 => ctrl_enable, 1 => ctrl_blink, 2 => ctrl_page, others => '0');
                    elsif addr_int = REG_STATUS then
                        reg_dat_o(0) <= not video_on;
                    elsif addr_int = REG_BGCOLOR then
                        reg_dat_o <= x"0000" & bg_color;
                    end if;
                end if;
            end if;
        end if;
    end process;

    reg_ack_o <= reg_ack;

end architecture rtl;
