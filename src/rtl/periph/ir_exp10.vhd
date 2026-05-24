-- 实验10：红外通信芯片（NEC遥控解码）
-- 遵循实验指导书 uPD6121G 编码格式：
--   引导码 9ms LOW + 4.5ms HIGH
--   低8位地址码 + 高8位地址码 + 8位数据码 + 8位数据反码 = 32bit
--   地址码固定 0x01（uPD6121G），仅校验数据码 vs 数据反码
-- 板载 IRM-V538N7/TR1，PIN_Y15
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity ir_exp10 is
    port (
        CLOCK_50 : in  std_logic;
        IRDA_RXD  : in  std_logic;
        KEY0_N    : in  std_logic;
        SW        : in  std_logic_vector(0 downto 0);
        LEDR      : out std_logic_vector(11 downto 0);
        LEDG      : out std_logic_vector(8 downto 0);
        HEX0      : out std_logic_vector(6 downto 0);
        HEX1      : out std_logic_vector(6 downto 0);
        HEX2      : out std_logic_vector(6 downto 0);
        HEX3      : out std_logic_vector(6 downto 0);
        HEX4      : out std_logic_vector(6 downto 0);
        HEX5      : out std_logic_vector(6 downto 0);
        HEX6      : out std_logic_vector(6 downto 0);
        HEX7      : out std_logic_vector(6 downto 0)
    );
end ir_exp10;

architecture behavioral of ir_exp10 is
    signal ir_sync   : std_logic_vector(2 downto 0) := "111";
    signal ir_fall   : std_logic;
    signal key0_sync : std_logic_vector(2 downto 0) := "111";
    signal key0_fall : std_logic;

    constant US_MAX : integer := 2000000;
    signal edge_cnt : integer range 0 to US_MAX := 0;

    -- 按指导书 uPD6121G 脉宽参数（50MHz）
    constant NEC_LEAD  : integer := 675000;  -- 9ms + 4.5ms = 13.5ms
    constant NEC_BIT_0 : integer := 56250;   -- 0.565ms + 0.56ms = 1.125ms
    constant NEC_BIT_1 : integer := 112500;  -- 0.565ms + 1.685ms = 2.25ms

    type state_t is (S_IDLE, S_DATA);
    signal state     : state_t := S_IDLE;
    signal bit_cnt   : integer range 0 to 31 := 0;
    signal shift_reg : std_logic_vector(31 downto 0) := (others => '0');

    signal ir_cmd     : std_logic_vector(7 downto 0);
    signal ir_valid   : std_logic;
    signal cmd_prev   : std_logic_vector(7 downto 0) := (others => '0');
    signal cmd_prev2  : std_logic_vector(7 downto 0) := (others => '0');
    signal led_reg    : std_logic_vector(11 downto 0) := (others => '0');
    signal ok_count   : integer range 0 to 99 := 0;
    signal reset_cnt  : integer range 0 to 25000000 := 0;
    signal heartbeat  : std_logic_vector(24 downto 0) := (others => '0');

    signal debug_mode    : std_logic;
    signal reset_active  : std_logic;
    signal bit_cnt_ge_16 : std_logic;
    signal bit_cnt_ge_8  : std_logic;

    -- 8位 bit-reverse：NEC LSB-first 导致 shift_reg 中字节位反转
    function bit_rev8(v : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable r : std_logic_vector(7 downto 0);
    begin
        for i in 0 to 7 loop
            r(i) := v(7 - i);
        end loop;
        return r;
    end function;

    function to_7seg(val : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        case val is
            when "0000" => return "1000000"; when "0001" => return "1111001";
            when "0010" => return "0100100"; when "0011" => return "0110000";
            when "0100" => return "0011001"; when "0101" => return "0010010";
            when "0110" => return "0000010"; when "0111" => return "1111000";
            when "1000" => return "0000000"; when "1001" => return "0010000";
            when "1010" => return "0001000"; when "1011" => return "0000011";
            when "1100" => return "1000110"; when "1101" => return "0100001";
            when "1110" => return "0000110"; when "1111" => return "0001110";
            when others => return "1111111";
        end case;
    end function;
begin
    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            heartbeat <= heartbeat + 1;
            ir_sync <= ir_sync(1 downto 0) & IRDA_RXD;
            key0_sync <= key0_sync(1 downto 0) & KEY0_N;
        end if;
    end process;
    ir_fall   <= '1' when ir_sync(2) = '1' and ir_sync(1) = '0' else '0';
    key0_fall <= '1' when key0_sync(2) = '1' and key0_sync(1) = '0' else '0';

    -- NEC 解码状态机
    -- shift_reg 布局（32bit 收完后）：
    --   [31:24] = bit-rev(高8位地址码)  [23:16] = bit-rev(低8位地址码)
    --   [15:8]  = bit-rev(数据码)        [7:0]   = bit-rev(数据反码)
    -- 只校验数据码 vs 数据反码（地址码无反码）
    process(CLOCK_50)
        variable cmd_ok : boolean;
        variable shift_v : std_logic_vector(31 downto 0);
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            if key0_fall = '1' then
                cmd_prev  <= (others => '0');
                cmd_prev2 <= (others => '0');
                ir_cmd    <= (others => '0');
            end if;
            if edge_cnt < US_MAX then
                edge_cnt <= edge_cnt + 1;
            end if;
            ir_valid <= '0';

            if ir_fall = '1' then
                shift_v := shift_reg;
                case state is
                    when S_IDLE =>
                        if edge_cnt >= NEC_LEAD - (NEC_LEAD/5) and
                           edge_cnt <= NEC_LEAD + (NEC_LEAD/5) then
                            state <= S_DATA;
                            bit_cnt <= 0;
                            shift_v := (others => '0');
                            shift_reg <= shift_v;
                        end if;

                    when S_DATA =>
                        if edge_cnt >= NEC_BIT_1 - (NEC_BIT_1/5) and
                           edge_cnt <= NEC_BIT_1 + (NEC_BIT_1/5) then
                            shift_v := shift_v(30 downto 0) & '1';
                        elsif edge_cnt >= NEC_BIT_0 - (NEC_BIT_0/3) and
                              edge_cnt <= NEC_BIT_0 + (NEC_BIT_0/3) then
                            shift_v := shift_v(30 downto 0) & '0';
                        else
                            state <= S_IDLE;
                        end if;
                        if state = S_DATA then
                            shift_reg <= shift_v;
                            if bit_cnt = 31 then
                                cmd_ok := shift_v(15 downto 8) = not shift_v(7 downto 0);
                                if cmd_ok then
                                    cmd_prev2 <= cmd_prev;
                                    cmd_prev <= ir_cmd;
                                    ir_cmd <= bit_rev8(shift_v(15 downto 8));
                                    ir_valid <= '1';
                                end if;
                                state <= S_IDLE;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        end if;
                end case;
                edge_cnt <= 0;
            end if;

            -- 超时推断最后一位为 1
            if state = S_DATA and edge_cnt > NEC_BIT_1 + (NEC_BIT_1/3) then
                shift_v := shift_reg;
                shift_v := shift_v(30 downto 0) & '1';
                cmd_ok := shift_v(15 downto 8) = not shift_v(7 downto 0);
                if cmd_ok then
                    cmd_prev2 <= cmd_prev;
                    cmd_prev <= ir_cmd;
                    ir_cmd <= bit_rev8(shift_v(15 downto 8));
                    ir_valid <= '1';
                end if;
                state <= S_IDLE;
                bit_cnt <= 0;
            end if;
        end if;
    end process;

    process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            if key0_fall = '1' then
                led_reg <= (others => '0');
                ok_count <= 0;
                reset_cnt <= 25000000;
            end if;
            if ir_valid = '1' then
                led_reg <= "0000" & ir_cmd;
                if ok_count < 99 then
                    ok_count <= ok_count + 1;
                end if;
            end if;
            if reset_cnt > 0 then
                reset_cnt <= reset_cnt - 1;
            end if;
        end if;
    end process;

    debug_mode    <= SW(0);
    bit_cnt_ge_16 <= '1' when bit_cnt >= 16 else '0';
    bit_cnt_ge_8  <= '1' when bit_cnt >= 8  else '0';
    reset_active  <= '1' when reset_cnt > 0 else '0';
    LEDR <= led_reg;

    process(debug_mode, ir_sync(0), ir_fall, state, ir_valid,
           bit_cnt_ge_16, bit_cnt_ge_8, reset_active, heartbeat)
    begin
        LEDG(8) <= not heartbeat(24);
        if debug_mode = '1' then
            LEDG(0) <= ir_sync(0);
            LEDG(1) <= ir_fall;
            if state = S_DATA then LEDG(2) <= '1'; else LEDG(2) <= '0'; end if;
            LEDG(3) <= ir_valid;
            LEDG(7) <= bit_cnt_ge_16;
            LEDG(6) <= bit_cnt_ge_8;
            LEDG(5) <= '0';
            LEDG(4) <= '0';
        else
            LEDG(7 downto 1) <= "0000000";
            LEDG(0) <= reset_active;
        end if;
    end process;

    process(CLOCK_50)
        variable cnt_ones : std_logic_vector(3 downto 0);
        variable cnt_tens : std_logic_vector(3 downto 0);
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            HEX5 <= to_7seg(ir_cmd(7 downto 4));
            HEX4 <= to_7seg(ir_cmd(3 downto 0));
            HEX3 <= to_7seg(cmd_prev(7 downto 4));
            HEX2 <= to_7seg(cmd_prev(3 downto 0));
            HEX1 <= to_7seg(cmd_prev2(7 downto 4));
            HEX0 <= to_7seg(cmd_prev2(3 downto 0));
            cnt_ones := "0000";
            case ok_count / 10 is
                when 0 => cnt_tens := "0000";
                when 1 => cnt_tens := "0001";
                when 2 => cnt_tens := "0010";
                when 3 => cnt_tens := "0011";
                when 4 => cnt_tens := "0100";
                when 5 => cnt_tens := "0101";
                when 6 => cnt_tens := "0110";
                when 7 => cnt_tens := "0111";
                when 8 => cnt_tens := "1000";
                when 9 => cnt_tens := "1001";
                when others => cnt_tens := "1111";
            end case;
            case ok_count rem 10 is
                when 0 => cnt_ones := "0000";
                when 1 => cnt_ones := "0001";
                when 2 => cnt_ones := "0010";
                when 3 => cnt_ones := "0011";
                when 4 => cnt_ones := "0100";
                when 5 => cnt_ones := "0101";
                when 6 => cnt_ones := "0110";
                when 7 => cnt_ones := "0111";
                when 8 => cnt_ones := "1000";
                when 9 => cnt_ones := "1001";
                when others => cnt_ones := "1111";
            end case;
            HEX7 <= to_7seg(cnt_tens);
            HEX6 <= to_7seg(cnt_ones);
        end if;
    end process;
end behavioral;
