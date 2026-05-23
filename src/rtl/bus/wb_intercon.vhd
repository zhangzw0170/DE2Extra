-- wb_intercon.vhd — Wishbone Single-Master Multi-Slave Interconnect
-- 纯组合地址解码，新外设只需在 cs 选择中加一项
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.de2extra_pkg.all;

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
        s0_ack_i   : in  std_logic;

        -- Slave 1: VGA text terminal @ 0xF0000000
        s1_adr_o   : out std_logic_vector(15 downto 0);
        s1_dat_i   : in  std_logic_vector(15 downto 0);
        s1_dat_o   : out std_logic_vector(15 downto 0);
        s1_we_o    : out std_logic;
        s1_stb_o   : out std_logic;
        s1_ack_i   : in  std_logic;

        -- Slave 2: PS/2 controller @ 0xF0002000
        s2_adr_o   : out std_logic_vector(3 downto 0);
        s2_dat_i   : in  std_logic_vector(31 downto 0);
        s2_dat_o   : out std_logic_vector(31 downto 0);
        s2_we_o    : out std_logic;
        s2_stb_o   : out std_logic;
        s2_ack_i   : in  std_logic
    );
end entity wb_intercon;

architecture rtl of wb_intercon is
    signal cs_sdram : std_logic;
    signal cs_vga   : std_logic;
    signal cs_ps2   : std_logic;
    constant SDRAM_END_C : unsigned(31 downto 0) := unsigned(ADDR_SDRAM_BASE) + to_unsigned(16#08000000#, 32);
    constant VGA_END_C   : unsigned(31 downto 0) := unsigned(ADDR_VGA_BASE)   + to_unsigned(16#00002000#, 32);
    constant PS2_END_C   : unsigned(31 downto 0) := unsigned(ADDR_PS2_BASE)   + to_unsigned(16#00001000#, 32);
begin

    -- SDRAM byte address window: 0x01000000 - 0x08FFFFFF (128MB)
    cs_sdram <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_SDRAM_BASE)) and
                        (unsigned(m_adr_i) <  SDRAM_END_C) else '0';
    cs_vga   <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_VGA_BASE)) and
                        (unsigned(m_adr_i) <  VGA_END_C) else '0';
    cs_ps2   <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_PS2_BASE)) and
                        (unsigned(m_adr_i) <  PS2_END_C) else '0';

    -- XBUS address is a full BYTE address. SDRAM controller expects a 25-bit
    -- WORD address, so drop byte-lane bits [1:0] and keep [26:2].
    s0_adr_o <= m_adr_i(26 downto 2);
    s0_dat_o <= m_dat_i;
    s0_we_o  <= m_we_i;
    s0_sel_o <= m_sel_i;
    s0_stb_o <= m_stb_i and m_cyc_i and cs_sdram;
    s0_cyc_o <= m_cyc_i and cs_sdram;

    -- VGA terminal uses byte offsets but transfers 16-bit entries/registers.
    s1_adr_o <= m_adr_i(15 downto 0);
    s1_dat_o <= m_dat_i(15 downto 0) when m_adr_i(1) = '0' else m_dat_i(31 downto 16);
    s1_we_o  <= m_we_i;
    s1_stb_o <= m_stb_i and m_cyc_i and cs_vga;

    -- PS/2 controller is a simple 32-bit register block.
    s2_adr_o <= m_adr_i(3 downto 0);
    s2_dat_o <= m_dat_i;
    s2_we_o  <= m_we_i;
    s2_stb_o <= m_stb_i and m_cyc_i and cs_ps2;

    -- Response mux
    process(all)
    begin
        m_dat_o <= (others => '0');
        m_ack_o <= '0';

        if cs_sdram = '1' then
            m_dat_o <= s0_dat_i;
            m_ack_o <= s0_ack_i;
        elsif cs_vga = '1' then
            if m_adr_i(1) = '0' then
                m_dat_o <= x"0000" & s1_dat_i;
            else
                m_dat_o <= s1_dat_i & x"0000";
            end if;
            m_ack_o <= s1_ack_i;
        elsif cs_ps2 = '1' then
            m_dat_o <= s2_dat_i;
            m_ack_o <= s2_ack_i;
        end if;
    end process;

    m_err_o <= m_stb_i and m_cyc_i and not (cs_sdram or cs_vga or cs_ps2);

end architecture rtl;
