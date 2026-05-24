-- led_patterns.vhd — Exp2 18-bit LED pattern engine
-- Rewritten for LEDR[17:0] so every mode occupies the full red LED bank.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity led_patterns is
    port (
        clk_i        : in  std_logic;                     -- 50 MHz
        rst_n_i      : in  std_logic;
        en_i         : in  std_logic;                     -- master enable
        mode_next_i  : in  std_logic;                     -- active-high push
        mode_o       : out std_logic_vector(3 downto 0);  -- current mode 0..8
        led_o        : out std_logic_vector(17 downto 0)  -- LEDR[17:0]
    );
end entity led_patterns;

architecture rtl of led_patterns is
    constant LED_WIDTH : integer := 18;
    constant STEP_MAX  : integer := 25000000 - 1; -- 2 Hz update
    constant DB_MAX    : integer := 12207 - 1;    -- ~4 kHz sample tick

    signal step_cnt      : integer range 0 to STEP_MAX := 0;
    signal step_tick     : std_logic := '0';
    signal db_cnt        : integer range 0 to DB_MAX := 0;
    signal db_tick       : std_logic := '0';
    signal btn_sync      : std_logic_vector(1 downto 0) := (others => '0');
    signal btn_prev      : std_logic := '0';
    signal mode_next_pulse : std_logic := '0';

    signal mode_r        : unsigned(3 downto 0) := (others => '0');
    signal led_r         : std_logic_vector(17 downto 0) := (others => '0');
    signal fill_phase    : std_logic := '0';

    function all_zero(v : std_logic_vector) return boolean is
    begin
        return v = (v'range => '0');
    end function;

    function all_one(v : std_logic_vector) return boolean is
    begin
        return v = (v'range => '1');
    end function;
begin
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                step_cnt <= 0;
                step_tick <= '0';
                db_cnt <= 0;
                db_tick <= '0';
                btn_sync <= (others => '0');
                btn_prev <= '0';
                mode_next_pulse <= '0';
                mode_r <= (others => '0');
                led_r <= (others => '0');
                fill_phase <= '0';
            else
                step_tick <= '0';
                if step_cnt = STEP_MAX then
                    step_cnt <= 0;
                    step_tick <= '1';
                else
                    step_cnt <= step_cnt + 1;
                end if;

                db_tick <= '0';
                if db_cnt = DB_MAX then
                    db_cnt <= 0;
                    db_tick <= '1';
                else
                    db_cnt <= db_cnt + 1;
                end if;

                btn_sync <= btn_sync(0) & mode_next_i;
                mode_next_pulse <= '0';
                if db_tick = '1' then
                    if (btn_sync(1) = '1') and (btn_prev = '0') then
                        mode_next_pulse <= '1';
                    end if;
                    btn_prev <= btn_sync(1);
                end if;

                if mode_next_pulse = '1' then
                    if mode_r = to_unsigned(8, 4) then
                        mode_r <= (others => '0');
                    else
                        mode_r <= mode_r + 1;
                    end if;
                    led_r <= (others => '0');
                    fill_phase <= '0';
                elsif step_tick = '1' then
                    if en_i = '0' then
                        led_r <= (others => '0');
                        fill_phase <= '0';
                    else
                        case to_integer(mode_r) is
                            when 0 =>
                                led_r <= (others => '0');
                                fill_phase <= '0';

                            when 1 => -- single light: LEDR17 -> LEDR0
                                if all_zero(led_r) then
                                    led_r <= (17 => '1', others => '0');
                                else
                                    led_r <= '0' & led_r(17 downto 1);
                                end if;

                            when 2 => -- single light: LEDR0 -> LEDR17
                                if all_zero(led_r) then
                                    led_r <= (0 => '1', others => '0');
                                else
                                    led_r <= led_r(16 downto 0) & '0';
                                end if;

                            when 3 => -- center pair -> outer edges
                                if all_zero(led_r) then
                                    led_r <= (9 => '1', 8 => '1', others => '0');
                                else
                                    led_r(17 downto 9) <= led_r(16 downto 9) & '0';
                                    led_r(8 downto 0)  <= '0' & led_r(8 downto 1);
                                end if;

                            when 4 => -- outer edges -> center pair
                                if all_zero(led_r) then
                                    led_r <= (17 => '1', 0 => '1', others => '0');
                                else
                                    led_r(17 downto 9) <= '0' & led_r(17 downto 10);
                                    led_r(8 downto 0)  <= led_r(7 downto 0) & '0';
                                end if;

                            when 5 => -- fill from LEDR17 toward LEDR0, then clear back
                                if fill_phase = '0' then
                                    led_r <= '1' & led_r(17 downto 1);
                                else
                                    led_r <= led_r(16 downto 0) & '0';
                                end if;

                            when 6 => -- fill from center pair to outer edges, then clear back
                                if fill_phase = '0' then
                                    led_r(17 downto 9) <= led_r(16 downto 9) & '1';
                                    led_r(8 downto 0)  <= '1' & led_r(8 downto 1);
                                else
                                    led_r(17 downto 9) <= '0' & led_r(17 downto 10);
                                    led_r(8 downto 0)  <= led_r(7 downto 0) & '0';
                                end if;

                            when 7 => -- fill from outer edges to center pair, then clear back
                                if fill_phase = '0' then
                                    led_r(17 downto 9) <= '1' & led_r(17 downto 10);
                                    led_r(8 downto 0)  <= led_r(7 downto 0) & '1';
                                else
                                    led_r(17 downto 9) <= led_r(16 downto 9) & '0';
                                    led_r(8 downto 0)  <= '0' & led_r(8 downto 1);
                                end if;

                            when 8 => -- full blink
                                if fill_phase = '0' then
                                    led_r <= (others => '1');
                                else
                                    led_r <= (others => '0');
                                end if;

                            when others =>
                                led_r <= (others => '0');
                                fill_phase <= '0';
                        end case;

                        if all_zero(led_r) then
                            fill_phase <= '0';
                        elsif all_one(led_r) then
                            fill_phase <= '1';
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    mode_o <= std_logic_vector(mode_r);
    led_o  <= led_r;
end architecture rtl;
