-- adapt_exp10.vhd — Exp10 (IR NEC) adapter
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.de2extra_pkg.all;

entity adapt_exp10 is
    port (
        clk_50   : in  std_logic;
        rst_n    : in  std_logic;
        sw       : in  std_logic_vector(17 downto 0);
        key_n    : in  std_logic_vector(3 downto 0);
        irda_rxd : in  std_logic;
        exp_out  : out exp_out_t
    );
end entity adapt_exp10;

architecture rtl of adapt_exp10 is
    signal ir_valid      : std_logic;
    signal ir_cmd        : std_logic_vector(7 downto 0);
    signal cmd_prev      : std_logic_vector(7 downto 0) := (others => '0');
    signal cmd_prev2     : std_logic_vector(7 downto 0) := (others => '0');
    signal cmd_cur       : std_logic_vector(7 downto 0) := (others => '0');
    signal hit_count     : integer range 0 to 99 := 0;
    signal heartbeat     : unsigned(24 downto 0) := (others => '0');
    signal valid_stretch : integer range 0 to 5000000 := 0;

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
            when "1110" => return "0000110"; when others => return "0001110";
        end case;
    end function;
begin
    -- Use the validated shell-side decoder path and keep the original Exp10
    -- board presentation (current + two-level history + debug LEDs).
    u_ir : entity work.ir_dbg_exp10
        port map (
            clk_i      => clk_50,
            rst_n_i    => rst_n,
            irda_rxd_i => irda_rxd,
            valid_o    => ir_valid,
            cmd_o      => ir_cmd
        );

    process(clk_50)
    begin
        if rising_edge(clk_50) then
            heartbeat <= heartbeat + 1;

            if (rst_n = '0') or (key_n(1) = '0') then
                cmd_cur       <= (others => '0');
                cmd_prev      <= (others => '0');
                cmd_prev2     <= (others => '0');
                hit_count     <= 0;
                valid_stretch <= 5000000;
            else
                if ir_valid = '1' then
                    cmd_prev2 <= cmd_prev;
                    cmd_prev  <= cmd_cur;
                    cmd_cur   <= ir_cmd;
                    valid_stretch <= 5000000;
                    if hit_count < 99 then
                        hit_count <= hit_count + 1;
                    end if;
                elsif valid_stretch > 0 then
                    valid_stretch <= valid_stretch - 1;
                end if;
            end if;
        end if;
    end process;

    exp_out.ledr(11 downto 0)  <= "0000" & cmd_cur;
    exp_out.ledr(17 downto 12) <= (others => '0');

    exp_out.hex(41 downto 35) <= to_7seg(cmd_cur(7 downto 4));
    exp_out.hex(34 downto 28) <= to_7seg(cmd_cur(3 downto 0));
    exp_out.hex(27 downto 21) <= to_7seg(cmd_prev(7 downto 4));
    exp_out.hex(20 downto 14) <= to_7seg(cmd_prev(3 downto 0));
    exp_out.hex(13 downto 7)  <= to_7seg(cmd_prev2(7 downto 4));
    exp_out.hex(6 downto 0)   <= to_7seg(cmd_prev2(3 downto 0));
    exp_out.hex(48 downto 42) <= to_7seg(std_logic_vector(to_unsigned(hit_count rem 10, 4)));
    exp_out.hex(55 downto 49) <= to_7seg(std_logic_vector(to_unsigned(hit_count / 10, 4)));

    exp_out.ledg(8) <= not heartbeat(24);
    exp_out.ledg(7 downto 4) <= cmd_cur(7 downto 4) when sw(0) = '1' else (others => '0');
    exp_out.ledg(3) <= '1' when valid_stretch > 0 else '0';
    exp_out.ledg(2) <= ir_valid;
    exp_out.ledg(1) <= key_n(1);
    exp_out.ledg(0) <= irda_rxd;

    exp_out.lcd_data <= (others => '0');
    exp_out.lcd_rs   <= '0';
    exp_out.lcd_rw   <= '0';
    exp_out.lcd_en   <= '0';
end architecture rtl;
