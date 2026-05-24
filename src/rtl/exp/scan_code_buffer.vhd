-- 扫描码缓冲器：流式显示所有PS/2字节，靠右对齐，3秒超时熄灭
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity scan_code_buffer is
    port (
        clk        : in  std_logic;
        scan_code  : in  std_logic_vector(7 downto 0);
        valid      : in  std_logic;
        buf        : out std_logic_vector(31 downto 0);
        num_bytes  : out integer range 0 to 4;
        display_on : out std_logic
    );
end scan_code_buffer;

architecture rtl of scan_code_buffer is
    signal buf_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal buf_len : integer range 0 to 4 := 0;
    signal timer   : integer range 0 to 150000000 := 0;
    constant TIMEOUT : integer := 150000000;  -- 3秒 @50MHz
begin
    process(clk)
    begin
        if clk'event and clk = '1' then
            if timer > 0 then
                display_on <= '1';
                timer <= timer - 1;
            else
                display_on <= '0';
            end if;

            if timer = 0 and buf_len /= 0 then
                buf_reg <= (others => '0');
                buf_len <= 0;
            end if;

            if valid = '1' then
                buf_reg <= buf_reg(23 downto 0) & scan_code;
                if buf_len < 4 then
                    buf_len <= buf_len + 1;
                end if;
                timer <= TIMEOUT;
            end if;
        end if;
    end process;

    buf       <= buf_reg;
    num_bytes <= buf_len;
end rtl;
