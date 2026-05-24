-- 实验13：LCD显示SOC芯片（扩展版）
-- 16x2字符LCD控制器
-- P1: 消息切换无闪烁  P2: 双行显示  P3: 多消息循环
-- P4: 滚动显示长文本  P5: SW实时数据显示
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lcd_soc is
    port (
        CLOCK_50  : in  std_logic;
        RST_N     : in  std_logic;
        KEY0_N    : in  std_logic;
        SW        : in  std_logic_vector(7 downto 0);
        LCD_DATA  : out std_logic_vector(7 downto 0);
        LCD_RS    : out std_logic;
        LCD_RW    : out std_logic;
        LCD_EN    : out std_logic;
        LCD_ON    : out std_logic;
        LCD_BLON  : out std_logic;
        HEX       : out std_logic_vector(6 downto 0);
        MSG_SEL_O : out std_logic_vector(1 downto 0);
        SCROLL_O  : out std_logic_vector(5 downto 0)
    );
end lcd_soc;

architecture behavioral of lcd_soc is
    -- 4位十六进制→ASCII
    function hex_nibble(n : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        case n is
            when x"0" => return x"30"; when x"1" => return x"31";
            when x"2" => return x"32"; when x"3" => return x"33";
            when x"4" => return x"34"; when x"5" => return x"35";
            when x"6" => return x"36"; when x"7" => return x"37";
            when x"8" => return x"38"; when x"9" => return x"39";
            when x"A" => return x"41"; when x"B" => return x"42";
            when x"C" => return x"43"; when x"D" => return x"44";
            when x"E" => return x"45"; when x"F" => return x"46";
            when others => return x"3F";
        end case;
    end function;

    -- 单bit→ASCII '0'/'1'
    function bit_to_char(b : std_logic) return std_logic_vector is
    begin
        if b = '1' then return x"31"; else return x"30"; end if;
    end function;

    type state_t is (
        S_POWER_WAIT, S_INIT, S_CMD_WAIT,
        S_REINIT, S_REINIT_WAIT,
        S_DATA, S_DATA_WAIT,
        S_LINE2, S_LINE2_WAIT,
        S_SCROLL_CMD, S_SCROLL_CMD_WAIT,
        S_IDLE
    );
    signal state         : state_t := S_POWER_WAIT;
    signal init_idx      : integer range 0 to 7 := 0;
    signal reinit_idx    : integer range 0 to 2 := 0;
    signal msg_idx       : integer range 0 to 31 := 0;
    signal en_cnt        : integer range 0 to 255 := 0;
    signal delay_cnt     : integer range 0 to 5000000 := 0;
    signal key0_prev     : std_logic := '1';
    signal msg_sel       : integer range 0 to 3 := 0;
    signal scroll_offset : integer range 0 to 48 := 0;
    signal scroll_timer  : integer range 0 to 20000000 := 0;
    signal refresh_timer : integer range 0 to 50000000 := 0;

    -- 初始化命令序列
    type init_entry_t is record
        cmd   : std_logic_vector(7 downto 0);
        delay : integer;
    end record;
    type init_array_t is array(0 to 6) of init_entry_t;
    constant INIT_SEQ : init_array_t := (
        (x"38", 410000),  -- Function Set: 8-bit, 2-line, 5x7
        (x"38",   5000),
        (x"38",   2000),
        (x"0C",   2000),  -- Display ON, Cursor OFF
        (x"06",   2000),  -- Entry Mode: Increment
        (x"01", 80000),  -- Clear Display
        (x"80",   2000)   -- Set DDRAM Address 0x00
    );

    -- 快速重初始化
    type reinit_entry_t is record
        cmd   : std_logic_vector(7 downto 0);
        delay : integer;
    end record;
    type reinit_array_t is array(0 to 1) of reinit_entry_t;
    constant REINIT_SEQ : reinit_array_t := (
        (x"01", 80000),  -- Clear Display
        (x"80",  2000)   -- Set DDRAM Address 0x00
    );

    -- 消息存储：128字节/条（行0: 0-63, 行1: 64-127）
    -- 静态消息内容在 0-15 和 64-79，其余填充空格
    -- 滚动消息(msg 2)使用完整 64+64 字节
    -- SW消息(msg 3)内容由 S_DATA 动态生成，此处全空格
    type msg128_t is array(0 to 127) of std_logic_vector(7 downto 0);
    type msg4_t is array(0 to 3) of msg128_t;
    constant MSGS : msg4_t := (
        -- msg 0: "DE2-115 LCD" / "Hello FPGA !"
        (x"44",x"45",x"32",x"2D",x"31",x"31",x"35",x"20",x"4C",x"43",x"44",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"48",x"65",x"6C",x"6C",x"6F",x"20",x"46",x"50",x"47",x"41",x"20",x"21",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20"),
        -- msg 1: "DE2-115 LCD" / "DE2-115 Board"
        (x"44",x"45",x"32",x"2D",x"31",x"31",x"35",x"20",x"4C",x"43",x"44",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"44",x"45",x"32",x"2D",x"31",x"31",x"35",x"20",x"42",x"6F",x"61",x"72",x"64",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20"),
        -- msg 2: 滚动显示 "Scrolling demo message on DE2-115 LCD board" / "Cyclone IV FPGA shows scrolling ability!"
        (x"53",x"63",x"72",x"6F",x"6C",x"6C",x"69",x"6E",x"67",x"20",x"64",x"65",x"6D",x"6F",x"20",x"6D",
         x"65",x"73",x"73",x"61",x"67",x"65",x"20",x"6F",x"6E",x"20",x"44",x"45",x"32",x"2D",x"31",x"31",
         x"35",x"20",x"4C",x"43",x"44",x"20",x"62",x"6F",x"61",x"72",x"64",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"43",x"79",x"63",x"6C",x"6F",x"6E",x"65",x"20",x"49",x"56",x"20",x"46",x"50",x"47",x"41",x"20",
         x"73",x"68",x"6F",x"77",x"73",x"20",x"73",x"63",x"72",x"6F",x"6C",x"6C",x"69",x"6E",x"67",x"20",
         x"61",x"62",x"69",x"6C",x"69",x"74",x"79",x"21",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20"),
        -- msg 3: SW实时显示（内容由S_DATA动态生成）
        (x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
         x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20")
    );

    -- HEX段码（共阳极，低电平点亮）
    type hex_array_t is array(0 to 3) of std_logic_vector(6 downto 0);
    constant HEX_CODES : hex_array_t := (
        "1111001",  -- '1'
        "0100100",  -- '2'
        "0110000",  -- '3'
        "0011001"   -- '4'
    );
begin
    process(CLOCK_50)
        variable v_idx : integer range 0 to 127;
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            if RST_N = '0' then
                state         <= S_POWER_WAIT;
                init_idx      <= 0;
                reinit_idx    <= 0;
                msg_idx       <= 0;
                en_cnt        <= 0;
                delay_cnt     <= 0;
                key0_prev     <= '1';
                msg_sel       <= 0;
                scroll_offset <= 0;
                scroll_timer  <= 0;
                refresh_timer <= 0;
                LCD_RS        <= '0';
                LCD_RW        <= '0';
                LCD_DATA      <= (others => '0');
                LCD_EN        <= '0';
            else
                -- KEY0 上升沿：循环切换消息
                key0_prev <= KEY0_N;
                if key0_prev = '0' and KEY0_N = '1' then
                    if state /= S_POWER_WAIT and state /= S_INIT and state /= S_CMD_WAIT then
                        if msg_sel = 3 then
                            msg_sel <= 0;
                        else
                            msg_sel <= msg_sel + 1;
                        end if;
                        state         <= S_REINIT;
                        reinit_idx    <= 0;
                        msg_idx       <= 0;
                        en_cnt        <= 0;
                        delay_cnt     <= 0;
                        scroll_offset <= 0;
                        scroll_timer  <= 0;
                        refresh_timer <= 0;
                    end if;
                end if;

                LCD_EN <= '0';

                case state is
                -- 上电等待 50ms
                when S_POWER_WAIT =>
                    if delay_cnt < 2500000 then
                        delay_cnt <= delay_cnt + 1;
                    else
                        delay_cnt <= 0;
                        init_idx <= 0;
                        state    <= S_INIT;
                    end if;

                -- 完整初始化序列
                when S_INIT =>
                    if init_idx <= 6 then
                        LCD_RS   <= '0';
                        LCD_RW   <= '0';
                        LCD_DATA <= INIT_SEQ(init_idx).cmd;
                        LCD_EN   <= '1';
                        en_cnt   <= 100;
                        delay_cnt <= 0;
                        state    <= S_CMD_WAIT;
                    else
                        msg_idx <= 0;
                        state   <= S_DATA;
                    end if;

                when S_CMD_WAIT =>
                    if en_cnt > 50 then LCD_EN <= '1'; end if;
                    if en_cnt > 0 then
                        en_cnt <= en_cnt - 1;
                    else
                        if delay_cnt < INIT_SEQ(init_idx).delay then
                            delay_cnt <= delay_cnt + 1;
                        else
                            delay_cnt <= 0;
                            init_idx <= init_idx + 1;
                            state <= S_INIT;
                        end if;
                    end if;

                -- 快速重初始化
                when S_REINIT =>
                    if reinit_idx < 2 then
                        LCD_RS   <= '0';
                        LCD_RW   <= '0';
                        LCD_DATA <= REINIT_SEQ(reinit_idx).cmd;
                        LCD_EN   <= '1';
                        en_cnt   <= 100;
                        delay_cnt <= 0;
                        state    <= S_REINIT_WAIT;
                    else
                        msg_idx <= 0;
                        state   <= S_DATA;
                    end if;

                when S_REINIT_WAIT =>
                    if en_cnt > 50 then LCD_EN <= '1'; end if;
                    if en_cnt > 0 then
                        en_cnt <= en_cnt - 1;
                    else
                        if delay_cnt < REINIT_SEQ(reinit_idx).delay then
                            delay_cnt <= delay_cnt + 1;
                        else
                            delay_cnt <= 0;
                            reinit_idx <= reinit_idx + 1;
                            state <= S_REINIT;
                        end if;
                    end if;

                -- 写数据
                when S_DATA =>
                    LCD_RS <= '1';
                    LCD_RW <= '0';
                    if msg_sel = 3 then
                        -- P5: SW实时显示
                        case msg_idx is
                            when 0      => LCD_DATA <= x"53";                    -- 'S'
                            when 1      => LCD_DATA <= x"57";                    -- 'W'
                            when 2      => LCD_DATA <= x"3D";                    -- '='
                            when 3      => LCD_DATA <= x"30";                    -- '0'
                            when 4      => LCD_DATA <= x"78";                    -- 'x'
                            when 5      => LCD_DATA <= hex_nibble(SW(7 downto 4));
                            when 6      => LCD_DATA <= hex_nibble(SW(3 downto 0));
                            when 7 to 15 => LCD_DATA <= x"20";                   -- spaces
                            when 16     => LCD_DATA <= x"42";                    -- 'B'
                            when 17     => LCD_DATA <= x"49";                    -- 'I'
                            when 18     => LCD_DATA <= x"4E";                    -- 'N'
                            when 19     => LCD_DATA <= x"3A";                    -- ':'
                            when 20     => LCD_DATA <= bit_to_char(SW(7));
                            when 21     => LCD_DATA <= bit_to_char(SW(6));
                            when 22     => LCD_DATA <= bit_to_char(SW(5));
                            when 23     => LCD_DATA <= bit_to_char(SW(4));
                            when 24     => LCD_DATA <= bit_to_char(SW(3));
                            when 25     => LCD_DATA <= bit_to_char(SW(2));
                            when 26     => LCD_DATA <= bit_to_char(SW(1));
                            when 27     => LCD_DATA <= bit_to_char(SW(0));
                            when others => LCD_DATA <= x"20";                    -- spaces
                        end case;
                    else
                        -- 静态/滚动：查 MSGS 数组
                        if msg_sel = 2 then
                            -- P4: 滚动偏移
                            if msg_idx < 16 then
                                v_idx := scroll_offset + msg_idx;
                            else
                                v_idx := 64 + scroll_offset + (msg_idx - 16);
                            end if;
                        else
                            -- 静态消息
                            if msg_idx < 16 then
                                v_idx := msg_idx;
                            else
                                v_idx := 64 + (msg_idx - 16);
                            end if;
                        end if;
                        LCD_DATA <= MSGS(msg_sel)(v_idx);
                    end if;
                    LCD_EN   <= '1';
                    en_cnt   <= 100;
                    delay_cnt <= 0;
                    state    <= S_DATA_WAIT;

                when S_DATA_WAIT =>
                    if en_cnt > 50 then LCD_EN <= '1'; end if;
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
                                state <= S_DATA;
                            else
                                state <= S_IDLE;
                            end if;
                        end if;
                    end if;

                -- 行切换：Set DDRAM 0xC0（行1）
                when S_LINE2 =>
                    LCD_RS   <= '0';
                    LCD_RW   <= '0';
                    LCD_DATA <= x"C0";
                    LCD_EN   <= '1';
                    en_cnt   <= 100;
                    delay_cnt <= 0;
                    state    <= S_LINE2_WAIT;

                when S_LINE2_WAIT =>
                    if en_cnt > 50 then LCD_EN <= '1'; end if;
                    if en_cnt > 0 then
                        en_cnt <= en_cnt - 1;
                    else
                        if delay_cnt < 2000 then
                            delay_cnt <= delay_cnt + 1;
                        else
                            delay_cnt <= 0;
                            msg_idx <= 16;
                            state <= S_DATA;
                        end if;
                    end if;

                -- 滚动刷新：Set DDRAM 0x80（行0，不清屏）
                when S_SCROLL_CMD =>
                    LCD_RS   <= '0';
                    LCD_RW   <= '0';
                    LCD_DATA <= x"80";
                    LCD_EN   <= '1';
                    en_cnt   <= 100;
                    delay_cnt <= 0;
                    state    <= S_SCROLL_CMD_WAIT;

                when S_SCROLL_CMD_WAIT =>
                    if en_cnt > 50 then LCD_EN <= '1'; end if;
                    if en_cnt > 0 then
                        en_cnt <= en_cnt - 1;
                    else
                        if delay_cnt < 2000 then
                            delay_cnt <= delay_cnt + 1;
                        else
                            delay_cnt <= 0;
                            msg_idx <= 0;
                            state <= S_DATA;
                        end if;
                    end if;

                -- 空闲状态：滚动定时 / SW刷新定时
                when S_IDLE =>
                    if msg_sel = 2 then
                        -- P4: 每100ms滚动一步
                        if scroll_timer < 5000000 then
                            scroll_timer <= scroll_timer + 1;
                        else
                            scroll_timer <= 0;
                            if scroll_offset < 48 then
                                scroll_offset <= scroll_offset + 1;
                            else
                                scroll_offset <= 0;
                            end if;
                            msg_idx   <= 0;
                            en_cnt    <= 0;
                            delay_cnt <= 0;
                            state     <= S_SCROLL_CMD;
                        end if;
                    elsif msg_sel = 3 then
                        -- P5: 每200ms刷新SW显示（不清屏）
                        if refresh_timer < 10000000 then
                            refresh_timer <= refresh_timer + 1;
                        else
                            refresh_timer <= 0;
                            msg_idx   <= 0;
                            en_cnt    <= 0;
                            delay_cnt <= 0;
                            state     <= S_SCROLL_CMD;
                        end if;
                    end if;
                end case;
            end if;
        end if;
    end process;

    -- HEX 显示当前消息编号 (1-4)
    HEX <= HEX_CODES(msg_sel);
    MSG_SEL_O <= std_logic_vector(to_unsigned(msg_sel, 2));
    SCROLL_O  <= std_logic_vector(to_unsigned(scroll_offset, 6));

    LCD_ON   <= '1';
    LCD_BLON <= '1';
end behavioral;
