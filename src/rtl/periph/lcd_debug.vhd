-- lcd_debug.vhd — Phase 2b LCD 调试显示器 (HD44780, 16x2)
--
-- 复用 Exp13 的 HD44780 初始化序列和驱动逻辑。
-- 显示内容:
--   Line 0: "DE2Extra 2b     " (固定)
--   Line 1: "VGA OK  PS2 OK  " (状态指示)
--
-- 输入: ps2_active (PS/2 接收到数据时脉冲), vga_vsync (VGA 帧同步)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lcd_debug is
    port (
        clk_i      : in  std_logic;
        rst_n_i    : in  std_logic;

        -- 状态输入
        vga_vs_i   : in  std_logic;       -- VGA VSYNC (帧同步)
        ps2_valid_i : in std_logic;        -- PS/2 收到有效字节

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
        (x"38", 410000),  -- Function Set: 8-bit, 2-line, 5x8 dots
        (x"38",   5000),
        (x"38",   2000),
        (x"0C",   2000),  -- Display ON, cursor OFF, blink OFF
        (x"06",   2000),  -- Entry mode: increment, no shift
        (x"01",  80000),  -- Clear display
        (x"80",   2000)   -- Set DDRAM address 0x00
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

    -- 行 0: "DE2Extra Ph2b   "
    function line0_char(idx : integer) return std_logic_vector is
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
            when 10 => return ch('h');
            when 11 => return ch('2');
            when 12 => return ch('b');
            when others => return ch(' ');
        end case;
    end function;

    -- 行 1: 状态指示
    function line1_char(
        vga_ok   : std_logic;
        ps2_ok   : std_logic;
        idx      : integer
    ) return std_logic_vector is
    begin
        case idx is
            when 0  => return ch('V');
            when 1  => return ch('G');
            when 2  => return ch('A');
            when 3  => return ch(' ');
            when 4 =>
                if vga_ok = '1' then return ch('O');
                else return ch('-'); end if;
            when 5 =>
                if vga_ok = '1' then return ch('K');
                else return ch('-'); end if;
            when 6  => return ch(' ');
            when 7  => return ch(' ');
            when 8  => return ch('P');
            when 9  => return ch('S');
            when 10 => return ch('2');
            when 11 => return ch(' ');
            when 12 =>
                if ps2_ok = '1' then return ch('O');
                else return ch('-'); end if;
            when 13 =>
                if ps2_ok = '1' then return ch('K');
                else return ch('-'); end if;
            when others => return ch(' ');
        end case;
    end function;

    signal state      : state_t := S_POWER_WAIT;
    signal init_idx   : integer range 0 to 6 := 0;
    signal msg_idx    : integer range 0 to 31 := 0;
    signal en_cnt     : integer range 0 to 100 := 0;
    signal delay_cnt  : integer := 0;
    signal power_cnt  : integer range 0 to 2500000 := 0;

    signal refresh_pending : std_logic := '1';

    -- VGA/PS2 状态检测
    signal vga_toggle_cnt  : integer range 0 to 50_000_000 := 0;
    signal vga_alive       : std_logic := '0';
    signal ps2_alive       : std_logic := '0';
    signal ps2_timeout     : integer range 0 to 250_000_000 := 0;

begin

    -- ============================================================
    -- VGA 存活检测: VSYNC 在 50M 周期内至少翻转一次
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
    -- PS/2 存活检测: 10 秒内有数据则为 OK
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
    -- HD44780 驱动状态机 (复用 Exp13 时序)
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
                refresh_pending <= '1';
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
                            lcd_data <= line0_char(msg_idx);
                        else
                            lcd_data <= line1_char(vga_alive, ps2_alive, msg_idx - 16);
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
                        lcd_data  <= x"C0";  -- DDRAM addr 0x40 (Line 2 start)
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
                        -- 每秒刷新一次
                        if refresh_pending = '1' then
                            refresh_pending <= '0';
                            init_idx        <= 0;
                            msg_idx         <= 0;
                            en_cnt          <= 0;
                            delay_cnt       <= 0;
                            state           <= S_REINIT;
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- 定时刷新 (约 1 秒)
    process(clk_i)
        variable refresh_timer : integer range 0 to 50_000_000 := 0;
    begin
        if rising_edge(clk_i) then
            if refresh_timer < 50_000_000 then
                refresh_timer := refresh_timer + 1;
            else
                refresh_timer := 0;
                refresh_pending <= '1';
            end if;
        end if;
    end process;

    lcd_on   <= '1';
    lcd_blon <= '1';

end architecture rtl;
