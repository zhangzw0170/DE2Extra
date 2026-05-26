library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.build_info_pkg.all;

entity build_info_wb is
    port (
        wb_adr_i : in  std_logic_vector(2 downto 0);
        wb_dat_o : out std_logic_vector(31 downto 0);
        wb_stb_i : in  std_logic;
        wb_ack_o : out std_logic
    );
end entity build_info_wb;

architecture rtl of build_info_wb is
begin
    process(all)
    begin
        wb_dat_o <= (others => '0');
        case wb_adr_i is
            when "000" =>
                wb_dat_o <= HW_BUILD_MAGIC_C;
            when "001" =>
                wb_dat_o <= HW_BUILD_DATE_C;
            when "010" =>
                wb_dat_o <= HW_BUILD_TIME_C;
            when others =>
                null;
        end case;
    end process;
    wb_ack_o <= wb_stb_i;
end architecture rtl;
