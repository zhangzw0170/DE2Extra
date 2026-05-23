-- lcd_status.vhd — SDRAM 测试结果 LCD 显示
--
-- GPIO/LCD 调试协议:
--   0x0------- : TESTING
--   0x1------- : ALL PASS
--   0x2------- : CRYPTO CLI READY
--   0x8tww0000 : fail meta, t=test#, ww=word index
--   0x9---hhhh : fail got[31:16]
--   0xA---llll : fail got[15:0]
--
-- LCD 显示:
--   正常: Line1 = "DE2Extra SDRAM  ", Line2 = "TESTING..." / "ALL PASS"
--   2a  : Line1 = "DE2Extra Crypto ", Line2 = "UART CLI READY "
--   失败: Line1 = "FAIL T? W??    ", Line2 = "GOT XXXXXXXX  "
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lcd_status is
    port (
        clk_i      : in  std_logic;
        gpio_i     : in  std_logic_vector(31 downto 0);
        lcd_data   : out std_logic_vector(7 downto 0);
        lcd_rs     : out std_logic;
        lcd_rw     : out std_logic;
        lcd_en     : out std_logic;
        lcd_on     : out std_logic;
        lcd_blon   : out std_logic
    );
end entity lcd_status;

architecture rtl of lcd_status is

    type state_t is (
        S_POWER_WAIT, S_INIT, S_CMD_WAIT,
        S_DATA, S_DATA_WAIT,
        S_LINE2, S_LINE2_WAIT,
        S_REINIT, S_REINIT_WAIT,
        S_IDLE
    );

    type disp_mode_t is (MODE_TESTING, MODE_PASS, MODE_CRYPTO, MODE_FAIL);

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

    function hex_char(n : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        case n is
            when "0000" => return ch('0');
            when "0001" => return ch('1');
            when "0010" => return ch('2');
            when "0011" => return ch('3');
            when "0100" => return ch('4');
            when "0101" => return ch('5');
            when "0110" => return ch('6');
            when "0111" => return ch('7');
            when "1000" => return ch('8');
            when "1001" => return ch('9');
            when "1010" => return ch('A');
            when "1011" => return ch('B');
            when "1100" => return ch('C');
            when "1101" => return ch('D');
            when "1110" => return ch('E');
            when others => return ch('F');
        end case;
    end function;

    function line1_char(
        mode      : disp_mode_t;
        fail_test : std_logic_vector(3 downto 0);
        fail_word : std_logic_vector(7 downto 0);
        idx       : integer
    ) return std_logic_vector is
    begin
        if mode = MODE_FAIL then
            case idx is
                when 0  => return ch('F');
                when 1  => return ch('A');
                when 2  => return ch('I');
                when 3  => return ch('L');
                when 4  => return ch(' ');
                when 5  => return ch('T');
                when 6  => return hex_char(fail_test);
                when 7  => return ch(' ');
                when 8  => return ch('W');
                when 9  => return hex_char(fail_word(7 downto 4));
                when 10 => return hex_char(fail_word(3 downto 0));
                when others => return ch(' ');
            end case;
        elsif mode = MODE_CRYPTO then
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
                when 9  => return ch('C');
                when 10 => return ch('r');
                when 11 => return ch('y');
                when 12 => return ch('p');
                when 13 => return ch('t');
                when 14 => return ch('o');
                when others => return ch(' ');
            end case;
        else
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
                when 9  => return ch('S');
                when 10 => return ch('D');
                when 11 => return ch('R');
                when 12 => return ch('A');
                when 13 => return ch('M');
                when others => return ch(' ');
            end case;
        end if;
    end function;

    function line2_char(
        mode     : disp_mode_t;
        fail_got : std_logic_vector(31 downto 0);
        idx      : integer
    ) return std_logic_vector is
    begin
        case mode is
            when MODE_TESTING =>
                case idx is
                    when 0 => return ch('T');
                    when 1 => return ch('E');
                    when 2 => return ch('S');
                    when 3 => return ch('T');
                    when 4 => return ch('I');
                    when 5 => return ch('N');
                    when 6 => return ch('G');
                    when 7 => return ch('.');
                    when 8 => return ch('.');
                    when 9 => return ch('.');
                    when others => return ch(' ');
                end case;
            when MODE_PASS =>
                case idx is
                    when 0 => return ch('A');
                    when 1 => return ch('L');
                    when 2 => return ch('L');
                    when 3 => return ch(' ');
                    when 4 => return ch('P');
                    when 5 => return ch('A');
                    when 6 => return ch('S');
                    when 7 => return ch('S');
                    when others => return ch(' ');
                end case;
            when MODE_CRYPTO =>
                case idx is
                    when 0  => return ch('U');
                    when 1  => return ch('A');
                    when 2  => return ch('R');
                    when 3  => return ch('T');
                    when 4  => return ch(' ');
                    when 5  => return ch('C');
                    when 6  => return ch('L');
                    when 7  => return ch('I');
                    when 8  => return ch(' ');
                    when 9  => return ch('R');
                    when 10 => return ch('E');
                    when 11 => return ch('A');
                    when 12 => return ch('D');
                    when 13 => return ch('Y');
                    when others => return ch(' ');
                end case;
            when MODE_FAIL =>
                case idx is
                    when 0  => return ch('G');
                    when 1  => return ch('O');
                    when 2  => return ch('T');
                    when 3  => return ch(' ');
                    when 4  => return hex_char(fail_got(31 downto 28));
                    when 5  => return hex_char(fail_got(27 downto 24));
                    when 6  => return hex_char(fail_got(23 downto 20));
                    when 7  => return hex_char(fail_got(19 downto 16));
                    when 8  => return hex_char(fail_got(15 downto 12));
                    when 9  => return hex_char(fail_got(11 downto 8));
                    when 10 => return hex_char(fail_got(7 downto 4));
                    when 11 => return hex_char(fail_got(3 downto 0));
                    when others => return ch(' ');
                end case;
        end case;
    end function;

    signal state           : state_t := S_POWER_WAIT;
    signal disp_mode       : disp_mode_t := MODE_TESTING;
    signal init_idx        : integer range 0 to 7 := 0;
    signal msg_idx         : integer range 0 to 31 := 0;
    signal en_cnt          : integer range 0 to 255 := 0;
    signal delay_cnt       : integer range 0 to 5000000 := 0;
    signal gpio_prev       : std_logic_vector(31 downto 0) := (others => '1');
    signal refresh_pending : std_logic := '0';
    signal fail_test_r     : std_logic_vector(3 downto 0) := (others => '0');
    signal fail_word_r     : std_logic_vector(7 downto 0) := (others => '0');
    signal fail_got_r      : std_logic_vector(31 downto 0) := (others => '0');

begin

    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if gpio_prev /= gpio_i then
                gpio_prev <= gpio_i;
                case gpio_i(31 downto 28) is
                    when "0000" =>
                        disp_mode <= MODE_TESTING;
                    when "0001" =>
                        disp_mode <= MODE_PASS;
                    when "0010" =>
                        disp_mode <= MODE_CRYPTO;
                    when "1000" =>
                        disp_mode   <= MODE_FAIL;
                        fail_test_r <= gpio_i(27 downto 24);
                        fail_word_r <= gpio_i(23 downto 16);
                    when "1001" =>
                        disp_mode <= MODE_FAIL;
                        fail_got_r(31 downto 16) <= gpio_i(15 downto 0);
                    when "1010" =>
                        disp_mode <= MODE_FAIL;
                        fail_got_r(15 downto 0) <= gpio_i(15 downto 0);
                    when others =>
                        null;
                end case;
                refresh_pending <= '1';
            end if;

            lcd_en <= '0';

            case state is

                when S_POWER_WAIT =>
                    if delay_cnt < 2500000 then
                        delay_cnt <= delay_cnt + 1;
                    else
                        delay_cnt <= 0;
                        init_idx  <= 0;
                        state     <= S_INIT;
                    end if;

                when S_INIT =>
                    if init_idx <= 6 then
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
                        lcd_data <= line1_char(disp_mode, fail_test_r, fail_word_r, msg_idx);
                    else
                        lcd_data <= line2_char(disp_mode, fail_got_r, msg_idx - 16);
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
    end process;

    lcd_on   <= '1';
    lcd_blon <= '1';

end architecture rtl;
