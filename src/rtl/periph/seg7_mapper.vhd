-- seg7_mapper.vhd — 16-bit hex 值 → 4 位七段数码管显示
--
-- 纯组合逻辑，使用 de2extra_pkg.hex_to_seg7 函数。
-- 输入: 4 个 hex nibble [15:12]=HEX3 .. [3:0]=HEX0
-- 输出: 4 组七段码 (active-low, common-anode, gfedcba)
library ieee;
use ieee.std_logic_1164.all;
use work.de2extra_pkg.all;

entity seg7_mapper is
    port (
        hex_nibbles : in  std_logic_vector(15 downto 0);
        seg0        : out std_logic_vector(6 downto 0);
        seg1        : out std_logic_vector(6 downto 0);
        seg2        : out std_logic_vector(6 downto 0);
        seg3        : out std_logic_vector(6 downto 0)
    );
end entity seg7_mapper;

architecture rtl of seg7_mapper is
begin

    seg0 <= hex_to_seg7(hex_nibbles(3 downto 0));
    seg1 <= hex_to_seg7(hex_nibbles(7 downto 4));
    seg2 <= hex_to_seg7(hex_nibbles(11 downto 8));
    seg3 <= hex_to_seg7(hex_nibbles(15 downto 12));

end architecture rtl;
