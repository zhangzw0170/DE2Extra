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
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.font_rom_pkg.all;

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
        reg_adr_i   : in  std_logic_vector(15 downto 0);  -- 字地址 (16-bit)
        reg_dat_i   : in  std_logic_vector(15 downto 0);
        reg_dat_o   : out std_logic_vector(15 downto 0);
        reg_we_i    : in  std_logic;
        reg_stb_i   : in  std_logic;
        reg_ack_o   : out std_logic
    );
end vga_text_terminal;

architecture rtl of vga_text_terminal is

    -- ═══════════════════════════════════════════════════════════
    -- VGA 640x480@60Hz 时序参数
    -- ═══════════════════════════════════════════════════════════
    constant H_TOTAL  : integer := 800;
    constant H_SYNC   : integer := 96;
    constant H_BP     : integer := 48;
    constant H_ACTIVE : integer := 640;
    constant H_FP     : integer := 16;

    constant V_TOTAL  : integer := 525;
    constant V_SYNC   : integer := 2;
    constant V_BP     : integer := 33;
    constant V_ACTIVE : integer := 480;
    constant V_FP     : integer := 10;

    -- ═══════════════════════════════════════════════════════════
    -- 文本终端参数
    -- ═══════════════════════════════════════════════════════════
    constant COLS     : integer := 80;
    constant ROWS     : integer := 25;    -- 25×16 = 400 < 480，底部留 80 行做状态栏
    constant CHAR_W   : integer := 8;
    constant CHAR_H   : integer := 16;
    constant BUF_SIZE : integer := 2000;  -- 80×25 = 2000 chars per page

    -- ═══════════════════════════════════════════════════════════
    -- 时钟
    -- ═══════════════════════════════════════════════════════════
    signal clk_25m    : std_logic := '0';

    -- ═══════════════════════════════════════════════════════════
    -- VGA 时序信号
    -- ═══════════════════════════════════════════════════════════
    signal h_count    : integer range 0 to H_TOTAL - 1 := 0;
    signal v_count    : integer range 0 to V_TOTAL - 1 := 0;
    signal h_sync     : std_logic;
    signal v_sync     : std_logic;
    signal video_on   : std_logic;
    signal pixel_x    : integer range 0 to H_ACTIVE - 1;
    signal pixel_y    : integer range 0 to V_ACTIVE - 1;

    -- ═══════════════════════════════════════════════════════════
    -- 文本缓冲区 (双页，每页 2000 words × 16-bit)
    -- ═══════════════════════════════════════════════════════════
    type buf_array_t is array (0 to BUF_SIZE - 1) of std_logic_vector(15 downto 0);
    signal buf_page0   : buf_array_t := (others => x"0020");  -- 空格+黑色前景
    signal buf_page1   : buf_array_t := (others => x"0020");
    signal buf_addr    : integer range 0 to BUF_SIZE - 1;
    signal buf_rdata   : std_logic_vector(15 downto 0);
    signal buf_char    : std_logic_vector(7 downto 0);   -- ASCII
    signal buf_color   : std_logic_vector(7 downto 0);   -- 前景色 RGB332

    -- ═══════════════════════════════════════════════════════════
    -- 字库 ROM (128 字符 × 16 行 × 8 像素 = 2048 × 8-bit)
    -- 数据来自 font_rom_pkg
    -- ═══════════════════════════════════════════════════════════
    signal font_addr    : integer range 0 to 2047;
    signal font_row     : std_logic_vector(7 downto 0);   -- 当前像素行

    -- ═══════════════════════════════════════════════════════════
    -- 控制寄存器 (偏移量 0x1000+)
    -- ═══════════════════════════════════════════════════════════
    signal cursor_x     : integer range 0 to COLS - 1 := 0;
    signal cursor_y     : integer range 0 to ROWS - 1 := 0;
    signal ctrl_enable  : std_logic := '1';           -- bit0
    signal ctrl_blink   : std_logic := '1';           -- bit1
    signal ctrl_page    : std_logic := '0';           -- bit2: 0=page0, 1=page1
    signal bg_color     : std_logic_vector(7 downto 0) := x"00";  -- RGB332
    signal clear_req    : std_logic := '0';

    -- ═══════════════════════════════════════════════════════════
    -- 光标闪烁 (25MHz 域，计数到 25000000 = 1Hz)
    -- ═══════════════════════════════════════════════════════════
    constant BLINK_MAX  : integer := 25_000_000;
    signal blink_cnt    : integer range 0 to BLINK_MAX - 1 := 0;
    signal blink_vis    : std_logic := '1';

    -- ═══════════════════════════════════════════════════════════
    -- 寄存器接口
    -- ═══════════════════════════════════════════════════════════
    signal reg_ack      : std_logic := '0';
    signal char_col     : integer range 0 to COLS - 1;
    signal char_row     : integer range 0 to ROWS - 1;
    signal char_px_row  : integer range 0 to CHAR_H - 1;
    signal cursor_match : std_logic;

begin

    -- ============================================================
    -- 25MHz 像素时钟 (50MHz 二分频)
    -- ============================================================
    process(clk_50m_i)
    begin
        if rising_edge(clk_50m_i) then
            clk_25m <= not clk_25m;
        end if;
    end process;
    vga_clk_o <= clk_25m;

    -- ============================================================
    -- 水平计数器
    -- ============================================================
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

    -- ============================================================
    -- 垂直计数器
    -- ============================================================
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

    -- ============================================================
    -- 同步信号
    -- ============================================================
    h_sync <= '1' when h_count >= H_SYNC else '0';
    v_sync <= '1' when v_count >= V_SYNC else '0';

    vga_hs_o   <= h_sync;
    vga_vs_o   <= v_sync;
    vga_sync_o <= not (h_sync and v_sync);

    -- 有效像素区域
    video_on <= '1' when
        h_count >= (H_SYNC + H_BP) and h_count < (H_SYNC + H_BP + H_ACTIVE) and
        v_count >= (V_SYNC + V_BP) and v_count < (V_SYNC + V_BP + V_ACTIVE)
        else '0';
    vga_blank_o <= video_on;

    pixel_x <= h_count - (H_SYNC + H_BP) when video_on = '1' else 0;
    pixel_y <= v_count - (V_SYNC + V_BP) when video_on = '1' else 0;

    -- ============================================================
    -- 字符坐标计算 (组合逻辑)
    -- ============================================================
    char_col    <= pixel_x / CHAR_W;
    char_row    <= pixel_y / CHAR_H;
    char_px_row <= pixel_y mod CHAR_H;

    -- 文本缓冲区读取地址
    buf_addr <= char_row * COLS + char_col
        when char_row < ROWS else 0;

    -- ============================================================
    -- 文本缓冲区读取 (双页)
    -- ============================================================
    -- 注: 读取在 clk_25m 上升沿进行, 使用流水线设计
    process(clk_25m)
    begin
        if rising_edge(clk_25m) then
            if ctrl_page = '0' then
                buf_rdata <= buf_page0(buf_addr);
            else
                buf_rdata <= buf_page1(buf_addr);
            end if;
        end if;
    end process;

    buf_char  <= buf_rdata(7 downto 0);
    buf_color <= buf_rdata(15 downto 8);

    -- ============================================================
    -- 字库 ROM 地址 = 字符码 * 16 + 像素行
    -- ============================================================
    font_addr <= conv_integer(buf_char) * CHAR_H + char_px_row
        when char_row < ROWS else 0;

    -- 字库读取 (同步 ROM, 数据来自 font_rom_pkg 常量)
    process(clk_25m)
    begin
        if rising_edge(clk_25m) then
            font_row <= font_rom_data(font_addr);
        end if;
    end process;

    -- ============================================================
    -- 光标闪烁计数器 (25MHz 域)
    -- ============================================================
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

    -- ============================================================
    -- VGA 像素输出 (组合逻辑: 需要 1 周期流水线延迟匹配 font_row)
    -- 实际流水线:
    --   cycle N:   buf_rdata 有效 (上周期读出的字符)
    --   cycle N+1: font_row 有效 (上周期读出的字库行)
    --   cycle N+2: 输出像素
    -- ============================================================
    cursor_match <= '1' when
        char_col = cursor_x and char_row = cursor_y
        else '0';

    process(clk_25m)
        variable px_bit    : integer range 0 to 7;         -- 水平像素偏移 (0=左, 7=右)
        variable font_px   : std_logic;                    -- 字库像素值
        variable r_out, g_out, b_out : std_logic_vector(7 downto 0);
        variable fg_r, fg_g, fg_b  : std_logic_vector(7 downto 0);
        variable bg_r, bg_g, bg_b  : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk_25m) then
            if video_on = '0' then
                vga_r_o <= x"00";
                vga_g_o <= x"00";
                vga_b_o <= x"00";
            else
                -- 水平像素偏移 (0=最左位, 7=最右位)
                -- font_row(7) = 最左边像素, font_row(0) = 最右边像素
                px_bit := pixel_x mod CHAR_W;

                -- 字符区域外的像素: 背景色
                if char_row >= ROWS or ctrl_enable = '0' then
                    font_px := '0';
                else
                    font_px := font_row(7 - px_bit);
                end if;

                -- RGB332 → RGB888 展开
                -- 前景色
                fg_r := buf_color(7 downto 5) & "00000";
                fg_g := buf_color(4 downto 2) & "00000";
                fg_b := buf_color(1 downto 0) & "000000";
                -- 背景色
                bg_r := bg_color(7 downto 5) & "00000";
                bg_g := bg_color(4 downto 2) & "00000";
                bg_b := bg_color(1 downto 0) & "000000";

                -- 光标反转
                if cursor_match = '1' and ctrl_blink = '1' and blink_vis = '1' then
                    font_px := not font_px;
                end if;

                if font_px = '1' then
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

    -- ============================================================
    -- 寄存器接口 (50MHz 时钟域, 与 VGA 异步但共享 buf_array)
    -- ============================================================
    process(clk_50m_i)
        variable reg_addr_int : integer;
    begin
        if rising_edge(clk_50m_i) then
            reg_ack  <= '0';
            reg_dat_o <= (others => '0');

            -- 清屏请求 (单周期脉冲, 清零后自动取消)
            if clear_req = '1' then
                if ctrl_page = '0' then
                    for i in 0 to BUF_SIZE - 1 loop
                        buf_page0(i) <= x"0020";
                    end loop;
                else
                    for i in 0 to BUF_SIZE - 1 loop
                        buf_page1(i) <= x"0020";
                    end loop;
                end if;
                clear_req <= '0';
            end if;

            if reg_stb_i = '1' then
                reg_ack <= '1';
                reg_addr_int := conv_integer(reg_adr_i);

                if reg_we_i = '1' then
                    -- 写入
                    if reg_addr_int < 2000 then
                        -- 文本缓冲区: 页 0
                        if ctrl_page = '0' then
                            buf_page0(reg_addr_int) <= reg_dat_i;
                        else
                            buf_page1(reg_addr_int) <= reg_dat_i;
                        end if;
                    elsif reg_addr_int = 16#1000# then
                        cursor_x <= conv_integer(reg_dat_i(6 downto 0));
                    elsif reg_addr_int = 16#1004# then
                        cursor_y <= conv_integer(reg_dat_i(4 downto 0));
                    elsif reg_addr_int = 16#1008# then
                        ctrl_enable <= reg_dat_i(0);
                        ctrl_blink  <= reg_dat_i(1);
                        ctrl_page   <= reg_dat_i(2);
                    elsif reg_addr_int = 16#1010# then
                        bg_color <= reg_dat_i(7 downto 0);
                    elsif reg_addr_int = 16#1014# then
                        clear_req <= '1';
                    end if;
                else
                    -- 读取
                    if reg_addr_int < 2000 then
                        if ctrl_page = '0' then
                            reg_dat_o <= buf_page0(reg_addr_int);
                        else
                            reg_dat_o <= buf_page1(reg_addr_int);
                        end if;
                    elsif reg_addr_int = 16#1000# then
                        reg_dat_o <= (others => '0');
                        reg_dat_o(6 downto 0) <= std_logic_vector(to_unsigned(cursor_x, 7));
                    elsif reg_addr_int = 16#1004# then
                        reg_dat_o <= (others => '0');
                        reg_dat_o(4 downto 0) <= std_logic_vector(to_unsigned(cursor_y, 5));
                    elsif reg_addr_int = 16#1008# then
                        reg_dat_o <= (0 => ctrl_enable, 1 => ctrl_blink, 2 => ctrl_page, others => '0');
                    elsif reg_addr_int = 16#100C# then
                        reg_dat_o <= (0 => not v_sync, others => '0');  -- vblank = 非同步期
                    elsif reg_addr_int = 16#1010# then
                        reg_dat_o <= x"00" & bg_color;
                    end if;
                end if;
            end if;
        end if;
    end process;

    reg_ack_o <= reg_ack;

end rtl;
