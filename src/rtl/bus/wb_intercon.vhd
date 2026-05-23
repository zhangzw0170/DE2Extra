-- wb_intercon.vhd — Wishbone Single-Master Multi-Slave Interconnect
-- 纯组合地址解码，新外设只需在 cs 选择中加一项
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wb_intercon is
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

        -- Slave 0: SDRAM (128MB @ 0x01000000, 25-bit word address)
        s0_adr_o   : out std_logic_vector(24 downto 0);
        s0_dat_i   : in  std_logic_vector(31 downto 0);
        s0_dat_o   : out std_logic_vector(31 downto 0);
        s0_we_o    : out std_logic;
        s0_sel_o   : out std_logic_vector(3 downto 0);
        s0_stb_o   : out std_logic;
        s0_cyc_o   : out std_logic;
        s0_ack_i   : in  std_logic
    );
end entity wb_intercon;

architecture rtl of wb_intercon is
    signal cs : std_logic;
    constant SDRAM_BASE_C : std_logic_vector(31 downto 0) := x"01000000";
    constant SDRAM_END_C  : std_logic_vector(31 downto 0) := x"09000000";
begin

    -- SDRAM byte address window: 0x01000000 - 0x08FFFFFF (128MB)
    cs <= '1' when (unsigned(m_adr_i) >= unsigned(SDRAM_BASE_C)) and
                   (unsigned(m_adr_i) <  unsigned(SDRAM_END_C)) else '0';

    -- XBUS address is a full BYTE address. SDRAM controller expects a 25-bit
    -- WORD address, so drop byte-lane bits [1:0] and keep [26:2].
    s0_adr_o <= m_adr_i(26 downto 2);
    s0_dat_o <= m_dat_i;
    s0_we_o  <= m_we_i;
    s0_sel_o <= m_sel_i;
    s0_stb_o <= m_stb_i and cs;
    s0_cyc_o <= m_cyc_i and cs;

    -- Response mux
    m_dat_o <= s0_dat_i;
    m_ack_o <= s0_ack_i;
    m_err_o <= m_stb_i and m_cyc_i and not cs;

end architecture rtl;
