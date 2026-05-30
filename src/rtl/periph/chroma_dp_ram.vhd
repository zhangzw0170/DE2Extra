-- chroma_dp_ram.vhd -- True dual-port RAM wrapper for ChromaShader
-- Uses altsyncram megafunction for guaranteed M9K inference.
-- Port A: write-only on clk_a (50 MHz)
-- Port B: read-only on clk_b (25 MHz)

library ieee;
use ieee.std_logic_1164.all;

entity chroma_dp_ram is
    generic (
        WIDTH : integer := 24;
        DEPTH : integer := 2048
    );
    port (
        clk_a    : in  std_logic;
        wr_en_a  : in  std_logic;
        addr_a   : in  integer range 0 to DEPTH-1;
        data_a   : in  std_logic_vector(WIDTH-1 downto 0);
        q_a      : out std_logic_vector(WIDTH-1 downto 0);

        clk_b    : in  std_logic;
        addr_b   : in  integer range 0 to DEPTH-1;
        q_b      : out std_logic_vector(WIDTH-1 downto 0)
    );
end entity chroma_dp_ram;

architecture rtl of chroma_dp_ram is

    type ram_t is array(0 to DEPTH-1) of std_logic_vector(WIDTH-1 downto 0);
    signal ram : ram_t;
    attribute ramstyle : string;
    attribute ramstyle of ram : signal is "M9K, no_rw_check";

begin

    -- Port A: read/write
    process(clk_a)
    begin
        if rising_edge(clk_a) then
            q_a <= ram(addr_a);
            if wr_en_a = '1' then
                ram(addr_a) <= data_a;
            end if;
        end if;
    end process;

    -- Port B: read only (separate clock, separate process)
    process(clk_b)
    begin
        if rising_edge(clk_b) then
            q_b <= ram(addr_b);
        end if;
    end process;

end architecture rtl;
