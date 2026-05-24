-- ir_dbg_exp10.vhd — Exp10-style NEC decoder for A/B testing
-- Exposes valid/cmd directly (no Wishbone wrapper)
-- Used to verify decoder logic works in DE2Extra context

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity ir_dbg_exp10 is
    port (
        clk_i      : in  std_logic;
        rst_n_i    : in  std_logic;
        irda_rxd_i : in  std_logic;
        valid_o    : out std_logic;
        cmd_o      : out std_logic_vector(7 downto 0)
    );
end entity ir_dbg_exp10;

architecture rtl of ir_dbg_exp10 is
    signal ir_sync  : std_logic_vector(2 downto 0) := "111";
    signal ir_fall  : std_logic;
    signal ecnt     : integer range 0 to 2000000 := 0;
    type st_t is (S_IDLE, S_DATA);
    signal state    : st_t := S_IDLE;
    signal bcnt     : integer range 0 to 31 := 0;
    signal shift_r  : std_logic_vector(31 downto 0) := (others => '0');
    signal vld      : std_logic := '0';
    signal cmd_r    : std_logic_vector(7 downto 0) := (others => '0');

    function rev8(v : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable r : std_logic_vector(7 downto 0);
    begin
        for i in 0 to 7 loop r(i) := v(7-i); end loop;
        return r;
    end function;
begin
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            ir_sync <= ir_sync(1 downto 0) & irda_rxd_i;
        end if;
    end process;
    ir_fall <= '1' when ir_sync(2) = '1' and ir_sync(1) = '0' else '0';

    process(clk_i)
        variable ok : boolean;
        variable sv : std_logic_vector(31 downto 0);
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                state <= S_IDLE; bcnt <= 0; vld <= '0'; ecnt <= 0;
            else
                vld <= '0';
                if ecnt < 2000000 then ecnt <= ecnt + 1; end if;

                if ir_fall = '1' then
                    sv := shift_r;
                    case state is
                        when S_IDLE =>
                            if ecnt >= 540000 and ecnt <= 810000 then
                                state <= S_DATA; bcnt <= 0;
                                sv := (others => '0'); shift_r <= sv;
                            end if;
                        when S_DATA =>
                            if ecnt >= 90000 and ecnt <= 135000 then
                                sv := sv(30 downto 0) & '1';
                            elsif ecnt >= 37500 and ecnt <= 75000 then
                                sv := sv(30 downto 0) & '0';
                            else
                                state <= S_IDLE;
                            end if;
                            if state = S_DATA then
                                shift_r <= sv;
                                if bcnt = 31 then
                                    ok := sv(15 downto 8) = not sv(7 downto 0);
                                    if ok then
                                        cmd_r <= rev8(sv(15 downto 8));
                                        vld <= '1';
                                    end if;
                                    state <= S_IDLE;
                                else
                                    bcnt <= bcnt + 1;
                                end if;
                            end if;
                    end case;
                    ecnt <= 0;
                end if;
            end if;
        end if;
    end process;

    valid_o <= vld;
    cmd_o   <= cmd_r;
end architecture rtl;
