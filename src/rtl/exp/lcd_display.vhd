-- LCD反汇编显示模块（带步骤反馈）
-- Line 0: 指令助记符+地址  e.g. "LOD 11"
-- Line 1: 当前FSM步骤     e.g. "MAR←11", "AC←MDR"
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity lcd_display is
    port (
        CLOCK_50 : in  std_logic;
        rst_n    : in  std_logic;
        trigger  : in  std_logic;
        detail   : in  std_logic;
        fsm_id   : in  std_logic_vector(3 downto 0);
        pc       : in  std_logic_vector(7 downto 0);
        ac       : in  std_logic_vector(15 downto 0);
        ir       : in  std_logic_vector(15 downto 0);
        LCD_DATA : out std_logic_vector(7 downto 0);
        LCD_RS   : out std_logic;
        LCD_RW   : out std_logic;
        LCD_EN   : out std_logic;
        LCD_ON   : out std_logic;
        LCD_BLON : out std_logic
    );
end lcd_display;

architecture behavioral of lcd_display is
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

    type state_t is (
        S_POWER_WAIT, S_INIT, S_CMD_WAIT,
        S_DATA, S_DATA_WAIT,
        S_LINE2, S_LINE2_WAIT,
        S_REFRESH_CMD, S_REFRESH_CMD_WAIT,
        S_IDLE
    );
    signal state     : state_t := S_POWER_WAIT;
    signal init_idx  : integer range 0 to 7 := 0;
    signal msg_idx   : integer range 0 to 31 := 0;
    signal en_cnt    : integer range 0 to 255 := 0;
    signal delay_cnt : integer range 0 to 5000000 := 0;
    signal refresh_timer : integer range 0 to 50000000 := 0;
    signal trigger_prev  : std_logic := '0';
    signal is_intermediate : std_logic;

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
        (x"01", 80000),
        (x"80",   2000)
    );
begin
    is_intermediate <= '1' when fsm_id = "0000" or fsm_id = "0001" or fsm_id = "0010"
                             or fsm_id = "0100" or fsm_id = "0101" or fsm_id = "0111"
                             or fsm_id = "1001" or fsm_id = "1010" else '0';

    process(CLOCK_50)
        variable pos : integer range 0 to 15;
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            if rst_n = '0' then
                state <= S_POWER_WAIT;
                init_idx <= 0;
                msg_idx <= 0;
                en_cnt <= 0;
                delay_cnt <= 0;
                refresh_timer <= 0;
                trigger_prev <= '0';
                LCD_EN <= '0';
            else
                trigger_prev <= trigger;
                LCD_EN <= '0';

                case state is
                    when S_POWER_WAIT =>
                        if delay_cnt < 2500000 then
                            delay_cnt <= delay_cnt + 1;
                        else
                            delay_cnt <= 0;
                            init_idx <= 0;
                            state <= S_INIT;
                        end if;

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

                    when S_DATA =>
                        LCD_RS <= '1';
                        LCD_RW <= '0';
                        pos := msg_idx mod 16;

                        if msg_idx < 16 then
                            -- Line 0: "III xx           "
                            case pos is
                                when 0 =>
                                    case ir(15 downto 8) is
                                        when x"00" => LCD_DATA <= x"41";
                                        when x"01" => LCD_DATA <= x"53";
                                        when x"02" => LCD_DATA <= x"4C";
                                        when x"03" => LCD_DATA <= x"4A";
                                        when x"04" => LCD_DATA <= x"4A";
                                        when others => LCD_DATA <= x"3F";
                                    end case;
                                when 1 =>
                                    case ir(15 downto 8) is
                                        when x"00" => LCD_DATA <= x"44";
                                        when x"01" => LCD_DATA <= x"54";
                                        when x"02" => LCD_DATA <= x"4F";
                                        when x"03" => LCD_DATA <= x"4D";
                                        when x"04" => LCD_DATA <= x"4E";
                                        when others => LCD_DATA <= x"3F";
                                    end case;
                                when 2 =>
                                    case ir(15 downto 8) is
                                        when x"00" => LCD_DATA <= x"44";
                                        when x"01" => LCD_DATA <= x"4F";
                                        when x"02" => LCD_DATA <= x"44";
                                        when x"03" => LCD_DATA <= x"50";
                                        when x"04" => LCD_DATA <= x"47";
                                        when others => LCD_DATA <= x"3F";
                                    end case;
                                when 3 => LCD_DATA <= x"20";
                                when 4 => LCD_DATA <= hex_nibble(ir(7 downto 4));
                                when 5 => LCD_DATA <= hex_nibble(ir(3 downto 0));
                                when others => LCD_DATA <= x"20";
                            end case;
                        else
                            -- Line 1: 按 fsm_id 显示步骤反馈
                            if detail = '0' and is_intermediate = '1' then
                                LCD_DATA <= x"20";
                            else
                            case fsm_id is
                                -- 0: FETCH1  "MAR <= PC      "
                                when "0000" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"4D"; -- M
                                        when 1  => LCD_DATA <= x"41"; -- A
                                        when 2  => LCD_DATA <= x"52"; -- R
                                        when 3  => LCD_DATA <= x"20"; -- space
                                        when 4  => LCD_DATA <= x"3C"; -- <
                                        when 5  => LCD_DATA <= x"3D"; -- =
                                        when 6  => LCD_DATA <= x"20"; -- space
                                        when 7  => LCD_DATA <= x"50"; -- P
                                        when 8  => LCD_DATA <= x"43"; -- C
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 1: FETCH2  "MDR <= MEM     "
                                when "0001" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"4D"; -- M
                                        when 1  => LCD_DATA <= x"44"; -- D
                                        when 2  => LCD_DATA <= x"52"; -- R
                                        when 3  => LCD_DATA <= x"20"; -- space
                                        when 4  => LCD_DATA <= x"3C"; -- <
                                        when 5  => LCD_DATA <= x"3D"; -- =
                                        when 6  => LCD_DATA <= x"20"; -- space
                                        when 7  => LCD_DATA <= x"4D"; -- M
                                        when 8  => LCD_DATA <= x"45"; -- E
                                        when 9  => LCD_DATA <= x"4D"; -- M
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 2: FETCH3  "IR <= MDR PC++ "
                                when "0010" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"49"; -- I
                                        when 1  => LCD_DATA <= x"52"; -- R
                                        when 2  => LCD_DATA <= x"20"; -- space
                                        when 3  => LCD_DATA <= x"3C"; -- <
                                        when 4  => LCD_DATA <= x"3D"; -- =
                                        when 5  => LCD_DATA <= x"20"; -- space
                                        when 6  => LCD_DATA <= x"4D"; -- M
                                        when 7  => LCD_DATA <= x"44"; -- D
                                        when 8  => LCD_DATA <= x"52"; -- R
                                        when 9  => LCD_DATA <= x"20"; -- space
                                        when 10 => LCD_DATA <= x"50"; -- P
                                        when 11 => LCD_DATA <= x"43"; -- C
                                        when 12 => LCD_DATA <= x"2B"; -- +
                                        when 13 => LCD_DATA <= x"2B"; -- +
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 3: DECODE  "DECODE         "
                                when "0011" =>
                                    case pos is
                                        when 0 => LCD_DATA <= x"44"; -- D
                                        when 1 => LCD_DATA <= x"45"; -- E
                                        when 2 => LCD_DATA <= x"43"; -- C
                                        when 3 => LCD_DATA <= x"4F"; -- O
                                        when 4 => LCD_DATA <= x"44"; -- D
                                        when 5 => LCD_DATA <= x"45"; -- E
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 4: ADD1     "MAR <= xx      "
                                when "0100" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"4D"; -- M
                                        when 1  => LCD_DATA <= x"41"; -- A
                                        when 2  => LCD_DATA <= x"52"; -- R
                                        when 3  => LCD_DATA <= x"20"; -- space
                                        when 4  => LCD_DATA <= x"3C"; -- <
                                        when 5  => LCD_DATA <= x"3D"; -- =
                                        when 6  => LCD_DATA <= x"20"; -- space
                                        when 7  => LCD_DATA <= hex_nibble(ir(7 downto 4));
                                        when 8  => LCD_DATA <= hex_nibble(ir(3 downto 0));
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 5: ADD2     "MDR <= MEM     "
                                when "0101" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"4D"; -- M
                                        when 1  => LCD_DATA <= x"44"; -- D
                                        when 2  => LCD_DATA <= x"52"; -- R
                                        when 3  => LCD_DATA <= x"20"; -- space
                                        when 4  => LCD_DATA <= x"3C"; -- <
                                        when 5  => LCD_DATA <= x"3D"; -- =
                                        when 6  => LCD_DATA <= x"20"; -- space
                                        when 7  => LCD_DATA <= x"4D"; -- M
                                        when 8  => LCD_DATA <= x"45"; -- E
                                        when 9  => LCD_DATA <= x"4D"; -- M
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 6: ADD3     "AC <= AC+MDR   "
                                when "0110" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"41"; -- A
                                        when 1  => LCD_DATA <= x"43"; -- C
                                        when 2  => LCD_DATA <= x"20"; -- space
                                        when 3  => LCD_DATA <= x"3C"; -- <
                                        when 4  => LCD_DATA <= x"3D"; -- =
                                        when 5  => LCD_DATA <= x"20"; -- space
                                        when 6  => LCD_DATA <= x"41"; -- A
                                        when 7  => LCD_DATA <= x"43"; -- C
                                        when 8  => LCD_DATA <= x"2B"; -- +
                                        when 9  => LCD_DATA <= x"4D"; -- M
                                        when 10 => LCD_DATA <= x"44"; -- D
                                        when 11 => LCD_DATA <= x"52"; -- R
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 7: STORE1   "MAR <= xx      "
                                when "0111" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"4D"; -- M
                                        when 1  => LCD_DATA <= x"41"; -- A
                                        when 2  => LCD_DATA <= x"52"; -- R
                                        when 3  => LCD_DATA <= x"20"; -- space
                                        when 4  => LCD_DATA <= x"3C"; -- <
                                        when 5  => LCD_DATA <= x"3D"; -- =
                                        when 6  => LCD_DATA <= x"20"; -- space
                                        when 7  => LCD_DATA <= hex_nibble(ir(7 downto 4));
                                        when 8  => LCD_DATA <= hex_nibble(ir(3 downto 0));
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 8: STORE2   "MEM <= AC      "
                                when "1000" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"4D"; -- M
                                        when 1  => LCD_DATA <= x"45"; -- E
                                        when 2  => LCD_DATA <= x"4D"; -- M
                                        when 3  => LCD_DATA <= x"20"; -- space
                                        when 4  => LCD_DATA <= x"3C"; -- <
                                        when 5  => LCD_DATA <= x"3D"; -- =
                                        when 6  => LCD_DATA <= x"20"; -- space
                                        when 7  => LCD_DATA <= x"41"; -- A
                                        when 8  => LCD_DATA <= x"43"; -- C
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 9: LOAD1    "MAR <= xx      "
                                when "1001" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"4D"; -- M
                                        when 1  => LCD_DATA <= x"41"; -- A
                                        when 2  => LCD_DATA <= x"52"; -- R
                                        when 3  => LCD_DATA <= x"20"; -- space
                                        when 4  => LCD_DATA <= x"3C"; -- <
                                        when 5  => LCD_DATA <= x"3D"; -- =
                                        when 6  => LCD_DATA <= x"20"; -- space
                                        when 7  => LCD_DATA <= hex_nibble(ir(7 downto 4));
                                        when 8  => LCD_DATA <= hex_nibble(ir(3 downto 0));
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 10: LOAD2   "MDR <= MEM     "
                                when "1010" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"4D"; -- M
                                        when 1  => LCD_DATA <= x"44"; -- D
                                        when 2  => LCD_DATA <= x"52"; -- R
                                        when 3  => LCD_DATA <= x"20"; -- space
                                        when 4  => LCD_DATA <= x"3C"; -- <
                                        when 5  => LCD_DATA <= x"3D"; -- =
                                        when 6  => LCD_DATA <= x"20"; -- space
                                        when 7  => LCD_DATA <= x"4D"; -- M
                                        when 8  => LCD_DATA <= x"45"; -- E
                                        when 9  => LCD_DATA <= x"4D"; -- M
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 11: LOAD3   "AC <= MDR      "
                                when "1011" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"41"; -- A
                                        when 1  => LCD_DATA <= x"43"; -- C
                                        when 2  => LCD_DATA <= x"20"; -- space
                                        when 3  => LCD_DATA <= x"3C"; -- <
                                        when 4  => LCD_DATA <= x"3D"; -- =
                                        when 5  => LCD_DATA <= x"20"; -- space
                                        when 6  => LCD_DATA <= x"4D"; -- M
                                        when 7  => LCD_DATA <= x"44"; -- D
                                        when 8  => LCD_DATA <= x"52"; -- R
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 12: JUMP    "PC <= xx       "
                                when "1100" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"50"; -- P
                                        when 1  => LCD_DATA <= x"43"; -- C
                                        when 2  => LCD_DATA <= x"20"; -- space
                                        when 3  => LCD_DATA <= x"3C"; -- <
                                        when 4  => LCD_DATA <= x"3D"; -- =
                                        when 5  => LCD_DATA <= x"20"; -- space
                                        when 6  => LCD_DATA <= hex_nibble(ir(7 downto 4));
                                        when 7  => LCD_DATA <= hex_nibble(ir(3 downto 0));
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                -- 13: JNEG    "AC<0? PC <= xx "
                                when "1101" =>
                                    case pos is
                                        when 0  => LCD_DATA <= x"41"; -- A
                                        when 1  => LCD_DATA <= x"43"; -- C
                                        when 2  => LCD_DATA <= x"3C"; -- <
                                        when 3  => LCD_DATA <= x"30"; -- 0
                                        when 4  => LCD_DATA <= x"3F"; -- ?
                                        when 5  => LCD_DATA <= x"20"; -- space
                                        when 6  => LCD_DATA <= x"50"; -- P
                                        when 7  => LCD_DATA <= x"43"; -- C
                                        when 8  => LCD_DATA <= x"20"; -- space
                                        when 9  => LCD_DATA <= x"3C"; -- <
                                        when 10 => LCD_DATA <= x"3D"; -- =
                                        when 11 => LCD_DATA <= x"20"; -- space
                                        when 12 => LCD_DATA <= hex_nibble(ir(7 downto 4));
                                        when 13 => LCD_DATA <= hex_nibble(ir(3 downto 0));
                                        when others => LCD_DATA <= x"20";
                                    end case;
                                when others =>
                                    LCD_DATA <= x"20";
                            end case;
                            end if;
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

                    when S_REFRESH_CMD =>
                        LCD_RS   <= '0';
                        LCD_RW   <= '0';
                        LCD_DATA <= x"80";
                        LCD_EN   <= '1';
                        en_cnt   <= 100;
                        delay_cnt <= 0;
                        state    <= S_REFRESH_CMD_WAIT;

                    when S_REFRESH_CMD_WAIT =>
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

                    when S_IDLE =>
                        if trigger_prev = '0' and trigger = '1' then
                            refresh_timer <= 0;
                            msg_idx   <= 0;
                            en_cnt    <= 0;
                            delay_cnt <= 0;
                            state     <= S_REFRESH_CMD;
                        elsif refresh_timer < 10000000 then
                            refresh_timer <= refresh_timer + 1;
                        else
                            refresh_timer <= 0;
                            msg_idx   <= 0;
                            en_cnt    <= 0;
                            delay_cnt <= 0;
                            state     <= S_REFRESH_CMD;
                        end if;
                end case;
            end if;
        end if;
    end process;

    LCD_ON   <= '1';
    LCD_BLON <= '1';
end behavioral;
