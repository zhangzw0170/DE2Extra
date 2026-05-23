-- vga_text_terminal.vhd — VGA 80x25 文字终端 (640x480@60Hz)
--
-- 复用 Exp6 VGA 时序 + 自建文本缓冲区 + 字库 ROM + 光标
-- 双页缓冲 (F1/F2)，寄存器接口可通过 Wishbone 访问
--
-- 字符格式: 每字符 16 位 = [7:0]=ASCII, [15:8]=前景色 RGB332
-- 背景色: 全局寄存器 bg_color (RGB332)
-- 时钟: 25MHz 像素时钟 (50MHz 二分频)

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vga_text_terminal is
    port (
        -- 50MHz 系统时钟
        clk_50m_i   : in  std_logic;
        rst_n_i     : in  std_logic;

        -- VGA 输出 (24-bit)
        vga_r_o     : out std_logic_vector(7 downto 0);
        vga_g_o     : out std_logic_vector(7 downto 0);
        vga_b_o     : out std_logic_vector(7 downto 0);
        vga_hs_o    : out std_logic;
        vga_vs_o    : out std_logic;
        vga_blank_o : out std_logic;
        vga_sync_o  : out std_logic;
        vga_clk_o   : out std_logic;

        -- 寄存器接口 (简单地址/数据，可桥接 Wishbone)
        reg_adr_i   : in  std_logic_vector(15 downto 0);  -- 字节偏移
        reg_dat_i   : in  std_logic_vector(15 downto 0);
        reg_dat_o   : out std_logic_vector(15 downto 0);
        reg_we_i    : in  std_logic;
        reg_stb_i   : in  std_logic;
        reg_ack_o   : out std_logic
    );
end vga_text_terminal;

architecture rtl of vga_text_terminal is

    constant H_TOTAL  : integer := 800;
    constant H_SYNC   : integer := 96;
    constant H_BP     : integer := 48;
    constant H_ACTIVE : integer := 640;

    constant V_TOTAL  : integer := 525;
    constant V_SYNC   : integer := 2;
    constant V_BP     : integer := 33;
    constant V_ACTIVE : integer := 480;

    constant COLS     : integer := 80;
    constant ROWS     : integer := 25;
    constant CHAR_W   : integer := 8;
    constant CHAR_H   : integer := 16;
    constant BUF_SIZE : integer := 2000;

    constant BLINK_MAX  : integer := 25_000_000;

    signal clk_25m      : std_logic := '0';
    signal h_count      : integer range 0 to H_TOTAL - 1 := 0;
    signal v_count      : integer range 0 to V_TOTAL - 1 := 0;
    signal hs_sig       : std_logic;
    signal vs_sig       : std_logic;
    signal video_on     : std_logic;
    signal pixel_x      : integer range 0 to H_ACTIVE - 1 := 0;
    signal pixel_y      : integer range 0 to V_ACTIVE - 1 := 0;
    signal blink_cnt    : integer range 0 to BLINK_MAX - 1 := 0;
    signal blink_vis    : std_logic := '1';
    signal cursor_x     : integer range 0 to COLS - 1 := 0;
    signal cursor_y     : integer range 0 to ROWS - 1 := 0;
    signal ctrl_enable  : std_logic := '1';
    signal ctrl_blink   : std_logic := '1';
    signal ctrl_page    : std_logic := '0';
    signal bg_color     : std_logic_vector(7 downto 0) := x"00";
    signal reg_ack      : std_logic := '0';
    signal cursor_box   : std_logic;
    signal border_box   : std_logic;

begin

    -- Bring-up VGA stub:
    -- keep timing and register map stable, but avoid the dual-clock text RAM
    -- implementation that exploded into >150k logic elements.

    process(clk_50m_i)
    begin
        if rising_edge(clk_50m_i) then
            clk_25m <= not clk_25m;
        end if;
    end process;
    vga_clk_o <= clk_25m;

    process(clk_25m)
    begin
        if rising_edge(clk_25m) then
            if h_count = H_TOTAL - 1 then
                h_count <= 0;
            else
                h_count <= h_count + 1;
            end if;
        end if;
    end process;

    process(clk_25m)
    begin
        if rising_edge(clk_25m) then
            if h_count = H_TOTAL - 1 then
                if v_count = V_TOTAL - 1 then
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
                end if;
            end if;
        end if;
    end process;

    hs_sig <= '1' when h_count >= H_SYNC else '0';
    vs_sig <= '1' when v_count >= V_SYNC else '0';

    vga_hs_o   <= hs_sig;
    vga_vs_o   <= vs_sig;
    vga_sync_o <= not (hs_sig and vs_sig);

    video_on <= '1' when
        h_count >= (H_SYNC + H_BP) and h_count < (H_SYNC + H_BP + H_ACTIVE) and
        v_count >= (V_SYNC + V_BP) and v_count < (V_SYNC + V_BP + V_ACTIVE)
        else '0';
    vga_blank_o <= video_on;

    pixel_x <= h_count - (H_SYNC + H_BP) when video_on = '1' else 0;
    pixel_y <= v_count - (V_SYNC + V_BP) when video_on = '1' else 0;

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

    cursor_box <= '1' when
        ctrl_enable = '1' and
        pixel_x >= (cursor_x * CHAR_W) and pixel_x < ((cursor_x + 1) * CHAR_W) and
        pixel_y >= (cursor_y * CHAR_H) and pixel_y < ((cursor_y + 1) * CHAR_H)
        else '0';

    border_box <= '1' when
        pixel_x < 8 or pixel_x >= (H_ACTIVE - 8) or
        pixel_y < 8 or pixel_y >= (V_ACTIVE - 8)
        else '0';

    process(clk_25m)
        variable fg_r, fg_g, fg_b : std_logic_vector(7 downto 0);
        variable bg_r, bg_g, bg_b : std_logic_vector(7 downto 0);
        variable show_fg          : std_logic;
    begin
        if rising_edge(clk_25m) then
            fg_r := x"FF";
            if ctrl_page = '0' then
                fg_g := x"FF";
                fg_b := x"FF";
            else
                fg_g := x"80";
                fg_b := x"00";
            end if;

            bg_r := bg_color(7 downto 5) & "00000";
            bg_g := bg_color(4 downto 2) & "00000";
            bg_b := bg_color(1 downto 0) & "000000";

            if video_on = '0' then
                vga_r_o <= x"00";
                vga_g_o <= x"00";
                vga_b_o <= x"00";
            else
                show_fg := border_box;
                if cursor_box = '1' and (ctrl_blink = '0' or blink_vis = '1') then
                    show_fg := '1';
                end if;

                if show_fg = '1' then
                    vga_r_o <= fg_r;
                    vga_g_o <= fg_g;
                    vga_b_o <= fg_b;
                else
                    vga_r_o <= bg_r;
                    vga_g_o <= bg_g;
                    vga_b_o <= bg_b;
                end if;
            end if;
        end if;
    end process;

    process(clk_50m_i)
        variable reg_addr_int : integer;
        variable next_cursor_x : integer;
        variable next_cursor_y : integer;
    begin
        if rising_edge(clk_50m_i) then
            reg_ack   <= '0';
            reg_dat_o <= (others => '0');

            if reg_stb_i = '1' then
                reg_ack <= '1';
                reg_addr_int := to_integer(unsigned(reg_adr_i));

                if reg_we_i = '1' then
                    if reg_addr_int = 16#1000# then
                        next_cursor_x := to_integer(unsigned(reg_dat_i(6 downto 0)));
                        if next_cursor_x < COLS then
                            cursor_x <= next_cursor_x;
                        end if;
                    elsif reg_addr_int = 16#1004# then
                        next_cursor_y := to_integer(unsigned(reg_dat_i(4 downto 0)));
                        if next_cursor_y < ROWS then
                            cursor_y <= next_cursor_y;
                        end if;
                    elsif reg_addr_int = 16#1008# then
                        ctrl_enable <= reg_dat_i(0);
                        ctrl_blink  <= reg_dat_i(1);
                        ctrl_page   <= reg_dat_i(2);
                    elsif reg_addr_int = 16#1010# then
                        bg_color <= reg_dat_i(7 downto 0);
                    end if;
                else
                    if reg_addr_int < (BUF_SIZE * 2) then
                        reg_dat_o <= (others => '0');
                    elsif reg_addr_int = 16#1000# then
                        reg_dat_o(6 downto 0) <= std_logic_vector(to_unsigned(cursor_x, 7));
                    elsif reg_addr_int = 16#1004# then
                        reg_dat_o(4 downto 0) <= std_logic_vector(to_unsigned(cursor_y, 5));
                    elsif reg_addr_int = 16#1008# then
                        reg_dat_o <= (0 => ctrl_enable, 1 => ctrl_blink, 2 => ctrl_page, others => '0');
                    elsif reg_addr_int = 16#100C# then
                        reg_dat_o <= (0 => not video_on, others => '0');
                    elsif reg_addr_int = 16#1010# then
                        reg_dat_o <= x"00" & bg_color;
                    end if;
                end if;
            end if;
        end if;
    end process;

    reg_ack_o <= reg_ack;

end rtl;
