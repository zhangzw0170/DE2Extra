-- lcd_debug.vhd — Phase 2b LCD 调试显示器 (HD44780, 16x2)
--
-- 显示内容 (SW16=1 时选中):
--   Line 0: "DE2Extra Ph2b   " + VGA/PS2 状态
--   Line 1: 最近 PS/2 键盘输入的 ASCII 字符 (滚动显示)
--
-- PS/2 Set 2 扫描码 → ASCII 硬件译码，支持:
--   - 主键盘字母/数字/符号 (US 布局)
--   - Shift 状态
--   - E0 前缀扩展键 (方向键显示为 ↑↓←→, Enter 显示为 ⏎)
--   - F0 释放码跟踪 Shift 状态

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lcd_debug is
    port (
        clk_i       : in  std_logic;
        rst_n_i     : in  std_logic;

        -- 状态输入
        vga_vs_i       : in  std_logic;
        ps2_valid_i    : in  std_logic;
        ps2_scancode_i : in  std_logic_vector(7 downto 0);

        -- HD44780 LCD 接口
        lcd_data   : out std_logic_vector(7 downto 0);
        lcd_rs     : out std_logic;
        lcd_rw     : out std_logic;
        lcd_en     : out std_logic;
        lcd_on     : out std_logic;
        lcd_blon   : out std_logic
    );
end entity lcd_debug;

architecture rtl of lcd_debug is

    -- ============================================================
    -- HD44780 驱动状态机
    -- ============================================================
    type state_t is (
        S_POWER_WAIT, S_INIT, S_CMD_WAIT,
        S_DATA, S_DATA_WAIT,
        S_LINE2, S_LINE2_WAIT,
        S_REINIT, S_REINIT_WAIT,
        S_IDLE
    );

    type init_entry_t is record
        cmd   : std_logic_vector(7 downto 0);
        delay : integer;
    end record;

    type init_array_t is array(0 to 6) of init_entry_t;
    constant INIT_SEQ : init_array_t := (
        (x"38", 410000),
        (x"38",   5000),
        (x"38",   2000),
        (x"0C",   2000),
        (x"06",   2000),
        (x"01",  80000),
        (x"80",   2000)
    );

    type reinit_array_t is array(0 to 1) of init_entry_t;
    constant REINIT_SEQ : reinit_array_t := (
        (x"01", 80000),
        (x"80",  2000)
    );

    function ch(c : character) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(character'pos(c), 8));
    end function;

    -- 行 0: "DE2Extra Ph2b  V?P?"
    function line0_char(
        vga_ok : std_logic;
        ps2_ok : std_logic;
        idx    : integer
    ) return std_logic_vector is
    begin
        case idx is
            when 0  => return ch('D');
            when 1  => return ch('E');
            when 2  => return ch('2');
            when 3  => return ch('E');
            when 4  => return ch('x');
            when 5  => return ch('t');
            when 6  => return ch('r');
            when 7  => return ch('a');
            when 8  => return ch(' ');
            when 9  => return ch('P');
            when 10 => return ch('S');
            when 11 => return ch('2');
            when 12 => return ch(' ');
            when 13 =>
                if vga_ok = '1' then return ch('V'); else return ch('-'); end if;
            when 14 =>
                if ps2_ok = '1' then return ch('P'); else return ch('-'); end if;
            when others => return ch(' ');
        end case;
    end function;

    -- ============================================================
    -- PS/2 Set 2 扫描码 → ASCII 译码
    -- ============================================================

    -- Set 2 scan code → ASCII (US keyboard layout)
    -- Scan codes from https://www.win.tue.nl/~aeb/linux/kbd/scancodes-10.html
    function sc2ascii(
        sc    : std_logic_vector(7 downto 0);
        shift : std_logic
    ) return std_logic_vector is
        variable v : std_logic_vector(7 downto 0);
    begin
        case sc is
            -- 数字主键盘行
            when x"16" => if shift='0' then v:=ch('1'); else v:=ch('!'); end if;
            when x"1E" => if shift='0' then v:=ch('2'); else v:=ch('@'); end if;
            when x"26" => if shift='0' then v:=ch('3'); else v:=ch('#'); end if;
            when x"25" => if shift='0' then v:=ch('4'); else v:=ch('$'); end if;
            when x"2E" => if shift='0' then v:=ch('5'); else v:=ch('%'); end if;
            when x"36" => if shift='0' then v:=ch('6'); else v:=ch('^'); end if;
            when x"3D" => if shift='0' then v:=ch('7'); else v:=ch('&'); end if;
            when x"3E" => if shift='0' then v:=ch('8'); else v:=ch('*'); end if;
            when x"46" => if shift='0' then v:=ch('9'); else v:=ch('('); end if;
            when x"45" => if shift='0' then v:=ch('0'); else v:=ch(')'); end if;

            -- 字母 QWERTY
            when x"1C" => if shift='0' then v:=ch('a'); else v:=ch('A'); end if;
            when x"32" => if shift='0' then v:=ch('b'); else v:=ch('B'); end if;
            when x"21" => if shift='0' then v:=ch('c'); else v:=ch('C'); end if;
            when x"23" => if shift='0' then v:=ch('d'); else v:=ch('D'); end if;
            when x"24" => if shift='0' then v:=ch('e'); else v:=ch('E'); end if;
            when x"2B" => if shift='0' then v:=ch('f'); else v:=ch('F'); end if;
            when x"34" => if shift='0' then v:=ch('g'); else v:=ch('G'); end if;
            when x"33" => if shift='0' then v:=ch('h'); else v:=ch('H'); end if;
            when x"43" => if shift='0' then v:=ch('i'); else v:=ch('I'); end if;
            when x"3B" => if shift='0' then v:=ch('j'); else v:=ch('J'); end if;
            when x"42" => if shift='0' then v:=ch('k'); else v:=ch('K'); end if;
            when x"4B" => if shift='0' then v:=ch('l'); else v:=ch('L'); end if;
            when x"3A" => if shift='0' then v:=ch('m'); else v:=ch('M'); end if;
            when x"31" => if shift='0' then v:=ch('n'); else v:=ch('N'); end if;
            when x"44" => if shift='0' then v:=ch('o'); else v:=ch('O'); end if;
            when x"4D" => if shift='0' then v:=ch('p'); else v:=ch('P'); end if;
            when x"15" => if shift='0' then v:=ch('q'); else v:=ch('Q'); end if;
            when x"2D" => if shift='0' then v:=ch('r'); else v:=ch('R'); end if;
            when x"1B" => if shift='0' then v:=ch('s'); else v:=ch('S'); end if;
            when x"2C" => if shift='0' then v:=ch('t'); else v:=ch('T'); end if;
            when x"3C" => if shift='0' then v:=ch('u'); else v:=ch('U'); end if;
            when x"2A" => if shift='0' then v:=ch('v'); else v:=ch('V'); end if;
            when x"1D" => if shift='0' then v:=ch('w'); else v:=ch('W'); end if;
            when x"22" => if shift='0' then v:=ch('x'); else v:=ch('X'); end if;
            when x"35" => if shift='0' then v:=ch('y'); else v:=ch('Y'); end if;
            when x"1A" => if shift='0' then v:=ch('z'); else v:=ch('Z'); end if;

            -- 特殊键
            when x"29" => v := ch(' ');   -- Space
            when x"5A" => v := ch('|');   -- Enter
            when x"66" => v := ch('*');   -- Backspace
            when x"0D" => v := ch('>');   -- Tab
            when x"76" => v := ch('E');   -- Esc

            -- 符号
            when x"0E" => if shift='0' then v:=ch('-'); else v:=ch('_'); end if;  -- grave/tilde
            when x"55" => if shift='0' then v:=ch('='); else v:=ch('+'); end if;
            when x"54" => if shift='0' then v:=ch('['); else v:=ch('{'); end if;
            when x"5B" => if shift='0' then v:=ch(']'); else v:=ch('}'); end if;
            when x"5D" => if shift='0' then v:=ch('/'); else v:=ch('|'); end if;  -- backslash
            when x"4C" => if shift='0' then v:=ch(';'); else v:=ch(':'); end if;
            when x"52" => if shift='0' then v:=x"27"; else v:=ch('"'); end if;  -- quote
            when x"41" => if shift='0' then v:=ch(','); else v:=ch('<'); end if;
            when x"49" => if shift='0' then v:=ch('.'); else v:=ch('>'); end if;
            when x"4A" => if shift='0' then v:=ch('/'); else v:=ch('?'); end if;
            when x"61" => if shift='0' then v:=ch(','); else v:=ch('<'); end if;  -- int'l

            when others => v := ch('.');
        end case;
        return v;
    end function;

    -- ============================================================
    -- 内部信号
    -- ============================================================

    -- HD44780 驱动
    signal state      : state_t := S_POWER_WAIT;
    signal init_idx   : integer range 0 to 6 := 0;
    signal msg_idx    : integer range 0 to 31 := 0;
    signal en_cnt     : integer range 0 to 100 := 0;
    signal delay_cnt  : integer := 0;
    signal power_cnt  : integer range 0 to 2500000 := 0;

    signal refresh_tick    : std_logic := '0';

    -- VGA/PS2 存活检测
    signal vga_toggle_cnt  : integer range 0 to 50_000_000 := 0;
    signal vga_alive       : std_logic := '0';
    signal ps2_alive       : std_logic := '0';
    signal ps2_timeout     : integer range 0 to 250_000_000 := 0;

    -- PS/2 扫描码 → ASCII 键盘缓冲
    constant BUF_LEN : integer := 16;
    type char_buf_t is array(0 to BUF_LEN-1) of std_logic_vector(7 downto 0);
    signal char_buf  : char_buf_t := (others => ch(' '));
    signal buf_wr    : integer range 0 to BUF_LEN-1 := 0;

    -- PS/2 协议状态
    type ps2_state_t is (PS2_IDLE, PS2_GOT_E0, PS2_GOT_F0, PS2_GOT_E0_F0);
    signal ps2_fsm   : ps2_state_t := PS2_IDLE;
    signal shift_held : std_logic := '0';

    -- 新字符待写入标记 (触发 LCD 刷新)
    signal new_char   : std_logic := '0';

    -- 行 1 字符: 键盘缓冲内容 (最近 16 字符)
    function line1_char_fn(
        buf   : char_buf_t;
        wr    : integer range 0 to BUF_LEN-1;
        idx   : integer
    ) return std_logic_vector is
        variable pos : integer;
    begin
        pos := (wr + idx) mod BUF_LEN;
        return buf(pos);
    end function;

begin

    -- ============================================================
    -- VGA 存活检测
    -- ============================================================
    process(clk_i)
        variable vs_prev : std_logic := '0';
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                vga_toggle_cnt <= 0;
                vga_alive <= '0';
            else
                if vga_vs_i /= vs_prev then
                    vga_toggle_cnt <= 0;
                    vga_alive <= '1';
                elsif vga_toggle_cnt < 50_000_000 then
                    vga_toggle_cnt <= vga_toggle_cnt + 1;
                else
                    vga_alive <= '0';
                end if;
                vs_prev := vga_vs_i;
            end if;
        end if;
    end process;

    -- ============================================================
    -- PS/2 存活检测
    -- ============================================================
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                ps2_alive <= '0';
                ps2_timeout <= 0;
            else
                if ps2_valid_i = '1' then
                    ps2_alive <= '1';
                    ps2_timeout <= 0;
                elsif ps2_timeout < 250_000_000 then
                    ps2_timeout <= ps2_timeout + 1;
                else
                    ps2_alive <= '0';
                end if;
            end if;
        end if;
    end process;

    -- ============================================================
    -- PS/2 Set 2 扫描码解析 → 字符缓冲
    -- ============================================================
    process(clk_i)
        variable ascii_v : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                ps2_fsm   <= PS2_IDLE;
                shift_held <= '0';
                buf_wr    <= 0;
                char_buf  <= (others => ch(' '));
                new_char  <= '0';
            else
                new_char <= '0';

                if ps2_valid_i = '1' then
                    case ps2_fsm is
                        when PS2_IDLE =>
                            if ps2_scancode_i = x"E0" then
                                ps2_fsm <= PS2_GOT_E0;
                            elsif ps2_scancode_i = x"F0" then
                                ps2_fsm <= PS2_GOT_F0;
                            else
                                -- Make code (无前缀)
                                -- Shift 按下
                                if ps2_scancode_i = x"12" or ps2_scancode_i = x"59" then
                                    shift_held <= '1';
                                else
                                    -- 普通按键按下 → 译码并写入缓冲
                                    ascii_v := sc2ascii(ps2_scancode_i, shift_held);
                                    char_buf(buf_wr) <= ascii_v;
                                    if buf_wr = BUF_LEN-1 then
                                        buf_wr <= 0;
                                    else
                                        buf_wr <= buf_wr + 1;
                                    end if;
                                    new_char <= '1';
                                end if;
                            end if;

                        when PS2_GOT_E0 =>
                            if ps2_scancode_i = x"F0" then
                                ps2_fsm <= PS2_GOT_E0_F0;
                            else
                                -- E0 + Make → 扩展键按下
                                -- 方向键等用特殊字符表示
                                case ps2_scancode_i is
                                    when x"75" => ascii_v := ch('^');  -- Up
                                    when x"72" => ascii_v := ch('v');  -- Down
                                    when x"6B" => ascii_v := ch('<');  -- Left
                                    when x"74" => ascii_v := ch('>');  -- Right
                                    when x"5A" => ascii_v := ch('<');  -- KP Enter
                                    when x"71" => ascii_v := ch('X');  -- Delete
                                    when x"6C" => ascii_v := ch('H');  -- Home
                                    when x"69" => ascii_v := ch('E');  -- End
                                    when others => ascii_v := ch('.');
                                end case;
                                char_buf(buf_wr) <= ascii_v;
                                if buf_wr = BUF_LEN-1 then
                                    buf_wr <= 0;
                                else
                                    buf_wr <= buf_wr + 1;
                                end if;
                                new_char <= '1';
                                ps2_fsm <= PS2_IDLE;
                            end if;

                        when PS2_GOT_F0 =>
                            -- F0 + Make code = key release
                            if ps2_scancode_i = x"12" or ps2_scancode_i = x"59" then
                                shift_held <= '0';
                            end if;
                            ps2_fsm <= PS2_IDLE;

                        when PS2_GOT_E0_F0 =>
                            -- E0 + F0 + code = extended key release
                            ps2_fsm <= PS2_IDLE;

                    end case;
                end if;
            end if;
        end if;
    end process;

    -- ============================================================
    -- HD44780 驱动状态机
    -- ============================================================
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                state     <= S_POWER_WAIT;
                init_idx  <= 0;
                msg_idx   <= 0;
                en_cnt    <= 0;
                delay_cnt <= 0;
                power_cnt <= 0;
                lcd_en    <= '0';
                lcd_rs    <= '0';
                lcd_rw    <= '0';
                lcd_data  <= (others => '0');
            else
                case state is
                    when S_POWER_WAIT =>
                        if power_cnt < 2500000 then
                            power_cnt <= power_cnt + 1;
                        else
                            state <= S_INIT;
                        end if;

                    when S_INIT =>
                        if init_idx < 7 then
                            lcd_rs    <= '0';
                            lcd_rw    <= '0';
                            lcd_data  <= INIT_SEQ(init_idx).cmd;
                            lcd_en    <= '1';
                            en_cnt    <= 100;
                            delay_cnt <= 0;
                            state     <= S_CMD_WAIT;
                        else
                            msg_idx <= 0;
                            state   <= S_DATA;
                        end if;

                    when S_CMD_WAIT =>
                        if en_cnt > 50 then
                            lcd_en <= '1';
                        end if;
                        if en_cnt > 0 then
                            en_cnt <= en_cnt - 1;
                        else
                            if delay_cnt < INIT_SEQ(init_idx).delay then
                                delay_cnt <= delay_cnt + 1;
                            else
                                delay_cnt <= 0;
                                init_idx  <= init_idx + 1;
                                state     <= S_INIT;
                            end if;
                        end if;

                    when S_REINIT =>
                        if init_idx < 2 then
                            lcd_rs    <= '0';
                            lcd_rw    <= '0';
                            lcd_data  <= REINIT_SEQ(init_idx).cmd;
                            lcd_en    <= '1';
                            en_cnt    <= 100;
                            delay_cnt <= 0;
                            state     <= S_REINIT_WAIT;
                        else
                            msg_idx <= 0;
                            state   <= S_DATA;
                        end if;

                    when S_REINIT_WAIT =>
                        if en_cnt > 50 then
                            lcd_en <= '1';
                        end if;
                        if en_cnt > 0 then
                            en_cnt <= en_cnt - 1;
                        else
                            if delay_cnt < REINIT_SEQ(init_idx).delay then
                                delay_cnt <= delay_cnt + 1;
                            else
                                delay_cnt <= 0;
                                init_idx  <= init_idx + 1;
                                state     <= S_REINIT;
                            end if;
                        end if;

                    when S_DATA =>
                        lcd_rs <= '1';
                        lcd_rw <= '0';
                        if msg_idx < 16 then
                            lcd_data <= line0_char(vga_alive, ps2_alive, msg_idx);
                        else
                            lcd_data <= line1_char_fn(char_buf, buf_wr, msg_idx - 16);
                        end if;
                        lcd_en    <= '1';
                        en_cnt    <= 100;
                        delay_cnt <= 0;
                        state     <= S_DATA_WAIT;

                    when S_DATA_WAIT =>
                        if en_cnt > 50 then
                            lcd_en <= '1';
                        end if;
                        if en_cnt > 0 then
                            en_cnt <= en_cnt - 1;
                        else
                            if delay_cnt < 2000 then
                                delay_cnt <= delay_cnt + 1;
                            else
                                delay_cnt <= 0;
                                if msg_idx = 15 then
                                    state <= S_LINE2;
                                elsif msg_idx < 31 then
                                    msg_idx <= msg_idx + 1;
                                    state   <= S_DATA;
                                else
                                    state <= S_IDLE;
                                end if;
                            end if;
                        end if;

                    when S_LINE2 =>
                        lcd_rs    <= '0';
                        lcd_rw    <= '0';
                        lcd_data  <= x"C0";
                        lcd_en    <= '1';
                        en_cnt    <= 100;
                        delay_cnt <= 0;
                        state     <= S_LINE2_WAIT;

                    when S_LINE2_WAIT =>
                        if en_cnt > 50 then
                            lcd_en <= '1';
                        end if;
                        if en_cnt > 0 then
                            en_cnt <= en_cnt - 1;
                        else
                            if delay_cnt < 2000 then
                                delay_cnt <= delay_cnt + 1;
                            else
                                delay_cnt <= 0;
                                msg_idx   <= 16;
                                state     <= S_DATA;
                            end if;
                        end if;

                    when S_IDLE =>
                        if refresh_tick = '1' or new_char = '1' then
                            init_idx  <= 0;
                            msg_idx   <= 0;
                            en_cnt    <= 0;
                            delay_cnt <= 0;
                            state     <= S_REINIT;
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- 定时刷新 (~1 秒) + 新字符立即触发
    process(clk_i)
        variable refresh_timer : integer range 0 to 50_000_000 := 0;
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                refresh_timer := 0;
                refresh_tick <= '0';
            else
                refresh_tick <= '0';
                if refresh_timer < 50_000_000 then
                    refresh_timer := refresh_timer + 1;
                else
                    refresh_timer := 0;
                    refresh_tick <= '1';
                end if;
            end if;
        end if;
    end process;

    lcd_on   <= '1';
    lcd_blon <= '1';

end architecture rtl;
