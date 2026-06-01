-- wb_intercon_icache.vhd — Minimal 1-master 2-slave Wishbone interconnect
-- SDRAM @ 0x01000000 (128MB), VGA @ 0xF0000000 (32KB)
-- CTI routed to SDRAM only (burst). Other addresses → stub ack.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.de2extra_pkg.all;

entity wb_intercon_icache is
    port (
        -- Master (NEORV32 XBUS)
        m_adr_i    : in  std_logic_vector(31 downto 0);
        m_dat_i    : in  std_logic_vector(31 downto 0);
        m_dat_o    : out std_logic_vector(31 downto 0);
        m_we_i     : in  std_logic;
        m_sel_i    : in  std_logic_vector(3 downto 0);
        m_stb_i    : in  std_logic;
        m_cyc_i    : in  std_logic;
        m_ack_o    : out std_logic;
        m_err_o    : out std_logic;
        m_cti_i    : in  std_logic_vector(2 downto 0);

        -- Slave 0: SDRAM (128MB @ 0x01000000, 25-bit word address)
        s0_adr_o   : out std_logic_vector(24 downto 0);
        s0_dat_i   : in  std_logic_vector(31 downto 0);
        s0_dat_o   : out std_logic_vector(31 downto 0);
        s0_we_o    : out std_logic;
        s0_sel_o   : out std_logic_vector(3 downto 0);
        s0_stb_o   : out std_logic;
        s0_cyc_o   : out std_logic;
        s0_ack_i   : in  std_logic;
        s0_cti_o   : out std_logic_vector(2 downto 0);

        -- Slave 1: VGA text/pixel @ 0xF0000000 (32KB)
        s1_adr_o   : out std_logic_vector(15 downto 0);
        s1_dat_i   : in  std_logic_vector(31 downto 0);
        s1_dat_o   : out std_logic_vector(31 downto 0);
        s1_we_o    : out std_logic;
        s1_stb_o   : out std_logic;
        s1_ack_i   : in  std_logic
    );
end entity wb_intercon_icache;

architecture rtl of wb_intercon_icache is
    signal cs_sdram : std_logic;
    signal cs_vga   : std_logic;
    constant SDRAM_END_C : unsigned(31 downto 0) := unsigned(ADDR_SDRAM_BASE) + to_unsigned(16#08000000#, 32);
    constant VGA_END_C   : unsigned(31 downto 0) := unsigned(ADDR_VGA_BASE)   + to_unsigned(16#00008000#, 32);
begin

    cs_sdram <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_SDRAM_BASE)) and
                        (unsigned(m_adr_i) <  SDRAM_END_C) else '0';
    cs_vga   <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_VGA_BASE)) and
                        (unsigned(m_adr_i) <  VGA_END_C) else '0';

    -- SDRAM: byte address → 25-bit word address
    s0_adr_o <= m_adr_i(26 downto 2);
    s0_dat_o <= m_dat_i;
    s0_we_o  <= m_we_i;
    s0_sel_o <= m_sel_i;
    s0_stb_o <= m_stb_i and m_cyc_i and cs_sdram;
    s0_cyc_o <= m_cyc_i and cs_sdram;
    s0_cti_o <= m_cti_i;

    -- VGA terminal: 32-bit direct pass-through
    s1_adr_o <= m_adr_i(15 downto 0);
    s1_dat_o <= m_dat_i;
    s1_we_o  <= m_we_i;
    s1_stb_o <= m_stb_i and m_cyc_i and cs_vga;

    -- Response mux: unmapped addresses get immediate ack (data=0) to avoid bus errors
    process(all)
    begin
        m_dat_o <= (others => '0');
        m_ack_o <= '0';

        if cs_sdram = '1' then
            m_dat_o <= s0_dat_i;
            m_ack_o <= s0_ack_i;
        elsif cs_vga = '1' then
            m_dat_o <= s1_dat_i;
            m_ack_o <= s1_ack_i;
        elsif m_stb_i = '1' and m_cyc_i = '1' then
            m_ack_o <= '1';
        end if;
    end process;

    m_err_o <= '0';

end architecture rtl;
