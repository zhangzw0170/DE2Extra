library ieee;
use ieee.std_logic_1164.all;

package build_info_pkg is
    constant HW_BUILD_MAGIC_C : std_logic_vector(31 downto 0) := x"42494E46";
    constant HW_BUILD_DATE_C  : std_logic_vector(31 downto 0) := x"20260526";
    constant HW_BUILD_TIME_C  : std_logic_vector(31 downto 0) := x"00190507";
end package build_info_pkg;
