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

        -- Slave 1: VGA text terminal @ 0xF0000000 (32-bit)
        s1_adr_o   : out std_logic_vector(15 downto 0);
        s1_dat_i   : in  std_logic_vector(31 downto 0);
        s1_dat_o   : out std_logic_vector(31 downto 0);
        s1_we_o    : out std_logic;
        s1_stb_o   : out std_logic;
        s1_ack_i   : in  std_logic;

        -- Slave 2: PS/2 controller @ 0xF0002000
        s2_adr_o   : out std_logic_vector(3 downto 0);
        s2_dat_i   : in  std_logic_vector(31 downto 0);
        s2_dat_o   : out std_logic_vector(31 downto 0);
        s2_we_o    : out std_logic;
        s2_stb_o   : out std_logic;
        s2_ack_i   : in  std_logic;

        -- Slave 3: IR receiver @ 0xF0009000
        s3_adr_o   : out std_logic_vector(2 downto 0);
        s3_dat_i   : in  std_logic_vector(31 downto 0);
        s3_dat_o   : out std_logic_vector(31 downto 0);
        s3_we_o    : out std_logic;
        s3_stb_o   : out std_logic;
        s3_ack_i   : in  std_logic;

        -- Slave 4: NTT accelerator @ 0xF000C000
        s4_adr_o   : out std_logic_vector(11 downto 0);
        s4_dat_i   : in  std_logic_vector(31 downto 0);
        s4_dat_o   : out std_logic_vector(31 downto 0);
        s4_we_o    : out std_logic;
        s4_stb_o   : out std_logic;
        s4_ack_i   : in  std_logic;

        -- Slave 5: LCD controller @ 0xF0008000
        s5_adr_o   : out std_logic_vector(3 downto 0);
        s5_dat_i   : in  std_logic_vector(31 downto 0);
        s5_dat_o   : out std_logic_vector(31 downto 0);
        s5_we_o    : out std_logic;
        s5_stb_o   : out std_logic;
        s5_ack_i   : in  std_logic;

        -- Slave 6: Timer @ 0xF0004000
        s6_adr_o   : out std_logic_vector(2 downto 0);
        s6_dat_i   : in  std_logic_vector(31 downto 0);
        s6_dat_o   : out std_logic_vector(31 downto 0);
        s6_we_o    : out std_logic;
        s6_stb_o   : out std_logic;
        s6_ack_i   : in  std_logic;

        -- Slave 7: INTC @ 0xF0006000
        s7_adr_o   : out std_logic_vector(2 downto 0);
        s7_dat_i   : in  std_logic_vector(31 downto 0);
        s7_dat_o   : out std_logic_vector(31 downto 0);
        s7_we_o    : out std_logic;
        s7_stb_o   : out std_logic;
        s7_ack_i   : in  std_logic;

        -- Slave 8: ExpDemo @ 0xF000D000
        s8_adr_o   : out std_logic_vector(2 downto 0);
        s8_dat_i   : in  std_logic_vector(31 downto 0);
        s8_dat_o   : out std_logic_vector(31 downto 0);
        s8_we_o    : out std_logic;
        s8_stb_o   : out std_logic;
        s8_ack_i   : in  std_logic
    );
end entity wb_intercon;

architecture rtl of wb_intercon is
    signal cs_sdram : std_logic;
    signal cs_vga   : std_logic;
    signal cs_ps2   : std_logic;
    signal cs_ir    : std_logic;
    signal cs_ntt   : std_logic;
    signal cs_lcd   : std_logic;
    signal cs_tmr   : std_logic;
    signal cs_intc  : std_logic;
    signal cs_expdemo: std_logic;
    constant SDRAM_END_C : unsigned(31 downto 0) := unsigned(ADDR_SDRAM_BASE) + to_unsigned(16#08000000#, 32);
    constant VGA_END_C   : unsigned(31 downto 0) := unsigned(ADDR_VGA_BASE)   + to_unsigned(16#00002000#, 32);
    constant PS2_END_C   : unsigned(31 downto 0) := unsigned(ADDR_PS2_BASE)   + to_unsigned(16#00001000#, 32);
    constant IR_END_C    : unsigned(31 downto 0) := unsigned(ADDR_IR_BASE)    + to_unsigned(16#00001000#, 32);
    constant LCD_END_C   : unsigned(31 downto 0) := unsigned(ADDR_LCD_BASE)   + to_unsigned(16#00001000#, 32);
    constant NTT_END_C   : unsigned(31 downto 0) := unsigned(ADDR_NTT_BASE)   + to_unsigned(16#00001000#, 32);
    constant TMR_END_C   : unsigned(31 downto 0) := unsigned(ADDR_TIMER_BASE) + to_unsigned(16#00001000#, 32);
    constant INTC_END_C  : unsigned(31 downto 0) := unsigned(ADDR_INTC_BASE)  + to_unsigned(16#00001000#, 32);
    constant EXPDEMO_END_C: unsigned(31 downto 0) := unsigned(ADDR_EXPDEMO_BASE) + to_unsigned(16#00001000#, 32);
begin

    -- SDRAM byte address window: 0x01000000 - 0x08FFFFFF (128MB)
    cs_sdram <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_SDRAM_BASE)) and
                        (unsigned(m_adr_i) <  SDRAM_END_C) else '0';
    cs_vga   <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_VGA_BASE)) and
                        (unsigned(m_adr_i) <  VGA_END_C) else '0';
    cs_ps2   <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_PS2_BASE)) and
                        (unsigned(m_adr_i) <  PS2_END_C) else '0';
    cs_ir    <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_IR_BASE)) and
                         (unsigned(m_adr_i) <  IR_END_C) else '0';
    cs_ntt   <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_NTT_BASE)) and
                         (unsigned(m_adr_i) <  NTT_END_C) else '0';
    cs_lcd   <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_LCD_BASE)) and
                         (unsigned(m_adr_i) <  LCD_END_C) else '0';
    cs_tmr   <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_TIMER_BASE)) and
                         (unsigned(m_adr_i) <  TMR_END_C) else '0';
    cs_intc  <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_INTC_BASE)) and
                         (unsigned(m_adr_i) <  INTC_END_C) else '0';
    cs_expdemo <= '1' when (unsigned(m_adr_i) >= unsigned(ADDR_EXPDEMO_BASE)) and
                          (unsigned(m_adr_i) <  EXPDEMO_END_C) else '0';

    -- XBUS address is a full BYTE address. SDRAM controller expects a 25-bit
    -- WORD address, so drop byte-lane bits [1:0] and keep [26:2].
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

    -- PS/2 controller is a simple 32-bit register block.
    s2_adr_o <= m_adr_i(3 downto 0);
    s2_dat_o <= m_dat_i;
    s2_we_o  <= m_we_i;
    s2_stb_o <= m_stb_i and m_cyc_i and cs_ps2;

    -- IR receiver uses word-aligned register offsets (0x00, 0x04).
    s3_adr_o <= m_adr_i(4 downto 2);
    s3_dat_o <= m_dat_i;
    s3_we_o  <= m_we_i;
    s3_stb_o <= m_stb_i and m_cyc_i and cs_ir;

    -- NTT accelerator is a 32-bit register block with 12-bit address.
    s4_adr_o <= m_adr_i(13 downto 2);
    s4_dat_o <= m_dat_i;
    s4_we_o  <= m_we_i;
    s4_stb_o <= m_stb_i and m_cyc_i and cs_ntt;

    -- LCD controller is a simple register block.
    s5_adr_o <= m_adr_i(3 downto 0);
    s5_dat_o <= m_dat_i;
    s5_we_o  <= m_we_i;
    s5_stb_o <= m_stb_i and m_cyc_i and cs_lcd;

    -- Timer: word-aligned register block (0x00, 0x04, 0x08)
    s6_adr_o <= m_adr_i(4 downto 2);
    s6_dat_o <= m_dat_i;
    s6_we_o  <= m_we_i;
    s6_stb_o <= m_stb_i and m_cyc_i and cs_tmr;

    -- INTC: word-aligned register block (0x00, 0x04)
    s7_adr_o <= m_adr_i(4 downto 2);
    s7_dat_o <= m_dat_i;
    s7_we_o  <= m_we_i;
    s7_stb_o <= m_stb_i and m_cyc_i and cs_intc;

    -- ExpDemo: word-aligned register block (0x00, 0x04)
    s8_adr_o <= m_adr_i(4 downto 2);
    s8_dat_o <= m_dat_i;
    s8_we_o  <= m_we_i;
    s8_stb_o <= m_stb_i and m_cyc_i and cs_expdemo;

    -- Response mux
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
        elsif cs_ps2 = '1' then
            m_dat_o <= s2_dat_i;
            m_ack_o <= s2_ack_i;
        elsif cs_ir = '1' then
            m_dat_o <= s3_dat_i;
            m_ack_o <= s3_ack_i;
        elsif cs_ntt = '1' then
            m_dat_o <= s4_dat_i;
            m_ack_o <= s4_ack_i;
        elsif cs_lcd = '1' then
            m_dat_o <= s5_dat_i;
            m_ack_o <= s5_ack_i;
        elsif cs_tmr = '1' then
            m_dat_o <= s6_dat_i;
            m_ack_o <= s6_ack_i;
        elsif cs_intc = '1' then
            m_dat_o <= s7_dat_i;
            m_ack_o <= s7_ack_i;
        elsif cs_expdemo = '1' then
            m_dat_o <= s8_dat_i;
            m_ack_o <= s8_ack_i;
        end if;
    end process;

    m_err_o <= m_stb_i and m_cyc_i and not (cs_sdram or cs_vga or cs_ps2 or cs_ir or cs_ntt or cs_lcd or cs_tmr or cs_intc or cs_expdemo);

end architecture rtl;
