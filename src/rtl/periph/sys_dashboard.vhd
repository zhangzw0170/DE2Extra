-- sys_dashboard.vhd — 系统仪表盘渲染引擎
--
-- 在 VGA 80×25 文字终端上实时绘制板级 I/O 状态:
--   左上: 16×2 LCD 镜像
--   LCD下: 8 个七段管 (2+2+4 排列, 大字体 2×3 char)
--   LEDR[17:0] 一行, 上方对齐 SW[17:0]
--   LEDG[8] 独立, 右侧 LEDG[7:0]
--   最下: KEY[3:0] 四个按键
--
-- 通过 VGA 终端寄存器接口写入文本缓冲区。
-- 刷新率 ~10Hz, 状态机逐字符写入。

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sys_dashboard is
    port (
        clk_i        : in  std_logic;    -- 50 MHz
        rst_n_i      : in  std_logic;

        -- 系统状态输入
        sw_i         : in  std_logic_vector(17 downto 0);
        key_n_i      : in  std_logic_vector(3 downto 0);
        ledr_i       : in  std_logic_vector(17 downto 0);
        ledg_i       : in  std_logic_vector(8 downto 0);
        hex_i        : in  std_logic_vector(55 downto 0);  -- 8×7seg

        -- IR 状态
        ir_cmd_i     : in  std_logic_vector(7 downto 0);
        ir_valid_i   : in  std_logic;
        ir_count_i   : in  std_logic_vector(7 downto 0);

        -- 时钟状态
        clock_hh_i   : in  std_logic_vector(7 downto 0);   -- BCD HH
        clock_mm_i   : in  std_logic_vector(7 downto 0);   -- BCD MM
        clock_ss_i   : in  std_logic_vector(7 downto 0);   -- BCD SS

        -- VGA 终端寄存器接口 (写入文本缓冲区)
        vga_wr_adr_o : out std_logic_vector(15 downto 0);  -- 字地址 0-1999
        vga_wr_dat_o : out std_logic_vector(15 downto 0);  -- [15:8]=颜色, [7:0]=ASCII
        vga_wr_en_o  : out std_logic;
        vga_busy_i   : in  std_logic    -- VGA 忙标志 (暂未使用)
    );
end sys_dashboard;

architecture rtl of sys_dashboard is

    -- 刷新定时器: 50MHz / 5_000_000 = 10Hz
    constant REFRESH_MAX : integer := 5_000_000 - 1;
    signal refresh_cnt   : integer range 0 to REFRESH_MAX := 0;
    signal refresh_trig  : std_logic := '0';

    -- 渲染状态机
    type render_state_t is (
        S_IDLE,
        S_CLEAR_AREA,
        S_DRAW_LCD,
        S_DRAW_HEX,
        S_DRAW_SW,
        S_DRAW_LEDR,
        S_DRAW_LEDG,
        S_DRAW_KEY,
        S_DRAW_IR,
        S_DRAW_CLOCK,
        S_DONE
    );
    signal state      : render_state_t := S_IDLE;
    signal char_idx   : integer range 0 to 79 := 0;  -- 列索引
    signal row_idx    : integer range 0 to 24 := 0;  -- 行索引

    -- 布局常量 (行号)
    constant ROW_LCD_0  : integer := 2;   -- LCD 行0
    constant ROW_LCD_1  : integer := 3;   -- LCD 行1
    constant ROW_HEX     : integer := 6;   -- 七段管顶部
    constant ROW_SW      : integer := 12;  -- 开关
    constant ROW_LEDR    : integer := 13;  -- LEDR
    constant ROW_LEDG    : integer := 14;  -- LEDG
    constant ROW_KEY     : integer := 16;  -- 按键
    constant ROW_STATUS  : integer := 18;  -- IR + Clock 状态行

    -- 颜色定义 (RGB332)
    constant COLOR_WHITE  : std_logic_vector(7 downto 0) := x"FF";
    constant COLOR_RED    : std_logic_vector(7 downto 0) := x"E0";
    constant COLOR_GREEN  : std_logic_vector(7 downto 0) := x"1C";
    constant COLOR_BLUE   : std_logic_vector(7 downto 0) := x"03";
    constant COLOR_YELLOW : std_logic_vector(7 downto 0) := x"FC";
    constant COLOR_CYAN   : std_logic_vector(7 downto 0) := x"1F";
    constant COLOR_GRAY   : std_logic_vector(7 downto 0) := x"92";
    constant COLOR_DIM    : std_logic_vector(7 downto 0) := x"49";

    -- 字符常量
    constant CH_SPACE     : std_logic_vector(7 downto 0) := x"20";
    constant CH_BLOCK     : std_logic_vector(7 downto 0) := x"DB";  -- █ 实心方块
    constant CH_DOT       : std_logic_vector(7 downto 0) := x"07";  -- • bullet
    constant CH_CIRCLE    : std_logic_vector(7 downto 0) := x"4F";  -- O
    constant CH_BAR       : std_logic_vector(7 downto 0) := x"DC";  -- ▄ 下半块
    constant CH_BAR_HALF  : std_logic_vector(7 downto 0) := x"B0";  -- ░ 浅网点

    -- 辅助函数: 整数→ASCII字符
    function int_to_ascii(n : integer range 0 to 9) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(48 + n, 8));  -- '0' = 48
    end function;

    function hex_to_ascii(n : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        if n < x"A" then
            return std_logic_vector(to_unsigned(48, 8)) + n;
        else
            return std_logic_vector(to_unsigned(55, 8)) + n;  -- 'A'-'F'
        end if;
    end function;

    -- 七段管字形: 0=灭 1=亮, 段序 gfedcba
    function seg_to_char(seg : std_logic_vector(6 downto 0); seg_id : std_logic) return std_logic_vector is
    begin
        -- 简化: 有数码管点亮 → 显示 ●, 否则显示 ○
        if seg(0) = '0' then  -- a段亮 (低有效)
            return x"2D";     -- '-' 表示有点亮
        else
            return CH_SPACE;
        end if;
    end function;

    -- 地址计算: 行 * 80 + 列
    function buf_addr(row : integer; col : integer) return integer is
    begin
        return row * 80 + col;
    end function;

    -- 渲染输出寄存器
    signal wr_adr   : integer range 0 to 1999 := 0;
    signal wr_data  : std_logic_vector(15 downto 0) := (others => '0');
    signal wr_en    : std_logic := '0';

begin

    -- ============================================================
    -- 刷新定时器: 10Hz
    -- ============================================================
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                refresh_cnt  <= 0;
                refresh_trig <= '0';
            elsif refresh_cnt = REFRESH_MAX then
                refresh_cnt  <= 0;
                refresh_trig <= '1';
            else
                refresh_cnt  <= refresh_cnt + 1;
                refresh_trig <= '0';
            end if;
        end if;
    end process;

    -- ============================================================
    -- 渲染状态机: 逐区域刷新 VGA text buffer
    -- ============================================================
    process(clk_i)
        variable col : integer range 0 to 79;
        variable row : integer range 0 to 24;
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                state    <= S_IDLE;
                char_idx <= 0;
                row_idx  <= 0;
                wr_en    <= '0';
            else
                wr_en <= '0';  -- 默认不写

                case state is
                    when S_IDLE =>
                        if refresh_trig = '1' then
                            state    <= S_DRAW_LCD;
                            char_idx <= 0;
                        end if;

                    ----------------------------------------------------
                    -- LCD 镜像: 16×2 字符, 直接写 ASCII
                    ----------------------------------------------------
                    when S_DRAW_LCD =>
                        col := char_idx;
                        -- 行0: "LCD: Line0       "
                        -- 行1: "    Line1       "
                        -- 暂时写占位符
                        if char_idx < 16 then
                            wr_adr  <= buf_addr(ROW_LCD_0, col + 2);
                            wr_data <= COLOR_CYAN & int_to_ascii(char_idx mod 10);
                            wr_en   <= '1';
                        elsif char_idx < 32 then
                            wr_adr  <= buf_addr(ROW_LCD_1, (char_idx - 16) + 2);
                            wr_data <= COLOR_CYAN & int_to_ascii((char_idx - 16) mod 10);
                            wr_en   <= '1';
                        end if;

                        if char_idx = 31 then
                            char_idx <= 0;
                            state    <= S_DRAW_HEX;
                        else
                            char_idx <= char_idx + 1;
                        end if;

                    ----------------------------------------------------
                    -- 七段管: 8 个数码管 (2+2+4), 每个 3×4 char 大字体
                    ----------------------------------------------------
                    when S_DRAW_HEX =>
                        -- 简化: 显示 HEX 值作为字符
                        -- HEX7-6: 时十位,个位 (col 2-7)
                        -- HEX5-4: 分十位,个位 (col 10-15)
                        -- HEX3-0: 4个低位 (col 18-33)
                        col := char_idx;
                        if char_idx < 8 then
                            -- 标题行
                            wr_adr  <= buf_addr(ROW_HEX, col * 4 + 1);
                            wr_data <= COLOR_GREEN & CH_SPACE;
                            wr_en   <= '1';
                        elsif char_idx < 16 then
                            -- 数据行: 显示 HEX 值的十六进制
                            wr_adr  <= buf_addr(ROW_HEX + 1, (char_idx - 8) * 2 + 1);
                            wr_data <= COLOR_GREEN & hex_to_ascii(hex_i(55 - (char_idx-8)*4 downto 52 - (char_idx-8)*4));
                            wr_en   <= '1';
                        end if;

                        if char_idx = 15 then
                            char_idx <= 0;
                            state    <= S_DRAW_SW;
                        else
                            char_idx <= char_idx + 1;
                        end if;

                    ----------------------------------------------------
                    -- SW 开关: 18 个, 字符 ■(ON) / ·(OFF), 绿色
                    ----------------------------------------------------
                    when S_DRAW_SW =>
                        col := char_idx;
                        if col < 18 then
                            wr_adr <= buf_addr(ROW_SW, col + 1);
                            if sw_i(col) = '1' then
                                wr_data <= COLOR_GREEN & x"11";  -- ◄
                            else
                                wr_data <= COLOR_DIM & x"10";    -- ►
                            end if;
                            wr_en <= '1';
                        end if;

                        if col = 17 then
                            char_idx <= 0;
                            state    <= S_DRAW_LEDR;
                        else
                            char_idx <= col + 1;
                        end if;

                    ----------------------------------------------------
                    -- LEDR: 18 个, 与 SW 对齐, 红色/暗
                    ----------------------------------------------------
                    when S_DRAW_LEDR =>
                        col := char_idx;
                        if col < 18 then
                            wr_adr <= buf_addr(ROW_LEDR, col + 1);
                            if ledr_i(col) = '1' then
                                wr_data <= COLOR_RED & CH_BLOCK;
                            else
                                wr_data <= COLOR_GRAY & CH_DOT;
                            end if;
                            wr_en <= '1';
                        end if;

                        if col = 17 then
                            char_idx <= 0;
                            state    <= S_DRAW_LEDG;
                        else
                            char_idx <= col + 1;
                        end if;

                    ----------------------------------------------------
                    -- LEDG: G8 单独, G7-0 右移
                    ----------------------------------------------------
                    when S_DRAW_LEDG =>
                        col := char_idx;
                        if col = 0 then
                            -- LEDG8 独立
                            wr_adr <= buf_addr(ROW_LEDG, 1);
                            if ledg_i(8) = '1' then
                                wr_data <= COLOR_GREEN & CH_BLOCK;
                            else
                                wr_data <= COLOR_GRAY & CH_DOT;
                            end if;
                            wr_en <= '1';
                        elsif col < 9 then
                            -- LEDG7-0 从 col 6 开始
                            wr_adr <= buf_addr(ROW_LEDG, col + 4);
                            if ledg_i(col - 1) = '1' then
                                wr_data <= COLOR_GREEN & CH_BLOCK;
                            else
                                wr_data <= COLOR_GRAY & CH_DOT;
                            end if;
                            wr_en <= '1';
                        end if;

                        if col = 8 then
                            char_idx <= 0;
                            state    <= S_DRAW_KEY;
                        else
                            char_idx <= col + 1;
                        end if;

                    ----------------------------------------------------
                    -- KEY 按键: K3-K0
                    ----------------------------------------------------
                    when S_DRAW_KEY =>
                        col := char_idx;
                        if col < 4 then
                            wr_adr <= buf_addr(ROW_KEY, col * 4 + 1);
                            -- key_n 低有效
                            if key_n_i(3 - col) = '0' then
                                wr_data <= COLOR_YELLOW & x"0F";  -- ☼ pressed
                            else
                                wr_data <= COLOR_DIM & x"6F";     -- o released
                            end if;
                            wr_en <= '1';
                        end if;

                        if col = 3 then
                            char_idx <= 0;
                            state    <= S_DRAW_IR;
                        else
                            char_idx <= col + 1;
                        end if;

                    ----------------------------------------------------
                    -- IR 状态
                    ----------------------------------------------------
                    when S_DRAW_IR =>
                        col := char_idx;
                        case col is
                            when 0 =>
                                wr_adr <= buf_addr(ROW_STATUS, 1);
                                wr_data <= COLOR_WHITE & x"49";  -- 'I'
                                wr_en   <= '1';
                            when 1 =>
                                wr_adr <= buf_addr(ROW_STATUS, 2);
                                wr_data <= COLOR_WHITE & x"52";  -- 'R'
                                wr_en   <= '1';
                            when 2 =>
                                wr_adr <= buf_addr(ROW_STATUS, 3);
                                wr_data <= COLOR_WHITE & x"3A";  -- ':'
                                wr_en   <= '1';
                            when 3 =>
                                wr_adr <= buf_addr(ROW_STATUS, 4);
                                wr_data <= COLOR_YELLOW & hex_to_ascii(ir_cmd_i(7 downto 4));
                                wr_en   <= '1';
                            when 4 =>
                                wr_adr <= buf_addr(ROW_STATUS, 5);
                                wr_data <= COLOR_YELLOW & hex_to_ascii(ir_cmd_i(3 downto 0));
                                wr_en   <= '1';
                            when 5 =>
                                if ir_valid_i = '1' then
                                    wr_adr <= buf_addr(ROW_STATUS, 7);
                                    wr_data <= COLOR_RED & x"21";  -- '!'
                                    wr_en   <= '1';
                                end if;
                            when others => null;
                        end case;

                        if col = 5 then
                            char_idx <= 0;
                            state    <= S_DRAW_CLOCK;
                        else
                            char_idx <= col + 1;
                        end if;

                    ----------------------------------------------------
                    -- 时钟
                    ----------------------------------------------------
                    when S_DRAW_CLOCK =>
                        col := char_idx;
                        case col is
                            when 0 =>
                                wr_adr <= buf_addr(ROW_STATUS, 20);
                                wr_data <= COLOR_CYAN & hex_to_ascii(clock_hh_i(7 downto 4));
                                wr_en   <= '1';
                            when 1 =>
                                wr_adr <= buf_addr(ROW_STATUS, 21);
                                wr_data <= COLOR_CYAN & hex_to_ascii(clock_hh_i(3 downto 0));
                                wr_en   <= '1';
                            when 2 =>
                                wr_adr <= buf_addr(ROW_STATUS, 22);
                                wr_data <= COLOR_WHITE & x"3A";  -- ':'
                                wr_en   <= '1';
                            when 3 =>
                                wr_adr <= buf_addr(ROW_STATUS, 23);
                                wr_data <= COLOR_CYAN & hex_to_ascii(clock_mm_i(7 downto 4));
                                wr_en   <= '1';
                            when 4 =>
                                wr_adr <= buf_addr(ROW_STATUS, 24);
                                wr_data <= COLOR_CYAN & hex_to_ascii(clock_mm_i(3 downto 0));
                                wr_en   <= '1';
                            when 5 =>
                                wr_adr <= buf_addr(ROW_STATUS, 25);
                                wr_data <= COLOR_WHITE & x"3A";  -- ':'
                                wr_en   <= '1';
                            when 6 =>
                                wr_adr <= buf_addr(ROW_STATUS, 26);
                                wr_data <= COLOR_CYAN & hex_to_ascii(clock_ss_i(7 downto 4));
                                wr_en   <= '1';
                            when 7 =>
                                wr_adr <= buf_addr(ROW_STATUS, 27);
                                wr_data <= COLOR_CYAN & hex_to_ascii(clock_ss_i(3 downto 0));
                                wr_en   <= '1';
                            when others => null;
                        end case;

                        if col = 7 then
                            state <= S_DONE;
                        else
                            char_idx <= col + 1;
                        end if;

                    ----------------------------------------------------
                    -- 等待下次刷新
                    ----------------------------------------------------
                    when S_DONE =>
                        state <= S_IDLE;

                    when others =>
                        state <= S_IDLE;
                end case;
            end if;
        end if;
    end process;

    -- ============================================================
    -- 输出映射
    -- ============================================================
    vga_wr_adr_o <= std_logic_vector(to_unsigned(wr_adr, 16));
    vga_wr_dat_o <= wr_data;
    vga_wr_en_o  <= wr_en;

end rtl;
