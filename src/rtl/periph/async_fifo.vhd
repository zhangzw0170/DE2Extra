-- async_fifo.vhd — Dual-clock async FIFO wrapper
--
-- The original hand-written dual-clock RAM inferred poorly in Quartus for the
-- VGA path and produced unstable display data. Use the vendor dcfifo directly
-- so the storage and CDC semantics are explicit and mapped into on-chip RAM.
library ieee;
use ieee.std_logic_1164.all;
library altera_mf;
use altera_mf.altera_mf_components.all;

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
    signal eccstatus_s : std_logic_vector(1 downto 0);
    signal rdusedw_s   : std_logic_vector(ADDR_W downto 0);
    signal wrusedw_s   : std_logic_vector(ADDR_W downto 0);
    signal rdfull_s    : std_logic;
    signal wrempty_s   : std_logic;

begin
    u_dcfifo : dcfifo
    generic map (
        intended_device_family => "Cyclone IV E",
        lpm_numwords           => DEPTH,
        lpm_showahead          => "ON",
        lpm_width              => DWIDTH,
        lpm_widthu             => ADDR_W + 1,
        overflow_checking      => "ON",
        underflow_checking     => "ON",
        rdsync_delaypipe       => 4,
        wrsync_delaypipe       => 4,
        use_eab                => "ON",
        add_usedw_msb_bit      => "ON"
    )
    port map (
        aclr     => not (wr_rst_n_i and rd_rst_n_i),
        data     => wr_data_i,
        eccstatus=> eccstatus_s,
        q        => rd_data_o,
        rdclk    => rd_clk_i,
        rdempty  => rd_empty_o,
        rdfull   => rdfull_s,
        rdreq    => rd_en_i,
        rdusedw  => rdusedw_s,
        wrclk    => wr_clk_i,
        wrempty  => wrempty_s,
        wrfull   => wr_full_o,
        wrreq    => wr_en_i,
        wrusedw  => wrusedw_s
    );

end architecture rtl;
