-- async_fifo.vhd — Dual-clock async FIFO (Gray code CDC)
--
-- 8-deep x 32-bit, power-of-2 depth only.
-- Clifford Cummings style: binary counters → Gray code → 2-FF synchronizer.
-- Full: wr_gray == ~(rd_gray_sync); Empty: rd_gray == wr_gray_sync.
--
-- Used by sdram_ctrl to decouple 100MHz burst capture from 50MHz CPU reads.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity async_fifo is
    generic (
        DWIDTH : natural := 32;
        DEPTH  : natural := 8        -- must be power of 2
    );
    port (
        -- Write domain (100MHz SDRAM side)
        wr_clk_i   : in  std_logic;
        wr_rst_n_i : in  std_logic;
        wr_en_i    : in  std_logic;
        wr_data_i  : in  std_logic_vector(DWIDTH-1 downto 0);
        wr_full_o  : out std_logic;

        -- Read domain (50MHz CPU side)
        rd_clk_i   : in  std_logic;
        rd_rst_n_i : in  std_logic;
        rd_en_i    : in  std_logic;
        rd_data_o  : out std_logic_vector(DWIDTH-1 downto 0);
        rd_empty_o : out std_logic
    );
end entity async_fifo;

architecture rtl of async_fifo is

    constant ADDR_W : natural := 3;  -- log2(DEPTH=8)

    type mem_t is array(0 to DEPTH-1) of std_logic_vector(DWIDTH-1 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    -- Binary counters
    signal wr_bin : unsigned(ADDR_W downto 0) := (others => '0');
    signal rd_bin : unsigned(ADDR_W downto 0) := (others => '0');

    -- Gray code versions
    signal wr_gray : std_logic_vector(ADDR_W downto 0) := (others => '0');
    signal rd_gray : std_logic_vector(ADDR_W downto 0) := (others => '0');

    -- Synchronized pointers (2-FF CDC)
    signal wr_gray_sync : std_logic_vector(ADDR_W downto 0) := (others => '0');
    signal rd_gray_sync : std_logic_vector(ADDR_W downto 0) := (others => '0');

    -- Intermediate sync stages
    signal wr_gray_meta : std_logic_vector(ADDR_W downto 0) := (others => '0');
    signal rd_gray_meta : std_logic_vector(ADDR_W downto 0) := (others => '0');

    function bin_to_gray(b : unsigned) return std_logic_vector is
    begin
        return std_logic_vector(b xor ('0' & b(b'high downto 1)));
    end function;

begin

    -- ================================================================
    -- Write domain (100MHz)
    -- ================================================================
    p_wr : process(wr_clk_i, wr_rst_n_i)
    begin
        if wr_rst_n_i = '0' then
            wr_bin  <= (others => '0');
            wr_gray <= (others => '0');
        elsif rising_edge(wr_clk_i) then
            if wr_en_i = '1' and wr_full_o = '0' then
                mem(to_integer(wr_bin(ADDR_W-1 downto 0))) <= wr_data_i;
                wr_bin  <= wr_bin + 1;
                wr_gray <= bin_to_gray(wr_bin + 1);
            end if;
        end if;
    end process;

    -- Synchronize rd_gray into write domain (2-FF)
    p_sync_rd : process(wr_clk_i, wr_rst_n_i)
    begin
        if wr_rst_n_i = '0' then
            rd_gray_meta <= (others => '0');
            rd_gray_sync <= (others => '0');
        elsif rising_edge(wr_clk_i) then
            rd_gray_meta <= rd_gray;
            rd_gray_sync <= rd_gray_meta;
        end if;
    end process;

    -- Full: write gray == invert MSB and MSB-1 of read gray synced
    wr_full_o <= '1' when wr_gray(ADDR_W downto ADDR_W-1) =
                          not rd_gray_sync(ADDR_W downto ADDR_W-1) and
                          wr_gray(ADDR_W-2 downto 0) =
                          rd_gray_sync(ADDR_W-2 downto 0)
                 else '0';

    -- ================================================================
    -- Read domain (50MHz)
    -- ================================================================
    p_rd : process(rd_clk_i, rd_rst_n_i)
    begin
        if rd_rst_n_i = '0' then
            rd_bin  <= (others => '0');
            rd_gray <= (others => '0');
        elsif rising_edge(rd_clk_i) then
            if rd_en_i = '1' and rd_empty_o = '0' then
                rd_bin  <= rd_bin + 1;
                rd_gray <= bin_to_gray(rd_bin + 1);
            end if;
        end if;
    end process;

    -- Output register (read-first behavior)
    rd_data_o <= mem(to_integer(rd_bin(ADDR_W-1 downto 0)));

    -- Synchronize wr_gray into read domain (2-FF)
    p_sync_wr : process(rd_clk_i, rd_rst_n_i)
    begin
        if rd_rst_n_i = '0' then
            wr_gray_meta <= (others => '0');
            wr_gray_sync <= (others => '0');
        elsif rising_edge(rd_clk_i) then
            wr_gray_meta <= wr_gray;
            wr_gray_sync <= wr_gray_meta;
        end if;
    end process;

    -- Empty: read gray == write gray synced
    rd_empty_o <= '1' when rd_gray = wr_gray_sync else '0';

end architecture rtl;
