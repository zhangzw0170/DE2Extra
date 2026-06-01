-- gpu_2d.vhd — Minimal 2D GPU accelerator (FILL operation)
--
-- Wishbone register interface (50MHz) + rendering FSM (100MHz).
-- CPU configures operation via registers, GPU autonomously writes
-- to SDRAM via burst-write port on sdram_ctrl.
--
-- Pixel format: RGB565 (16-bit), 2 pixels per 32-bit SDRAM word.
-- Burst: 8 words = 16 pixels per burst.
--
-- Register map (Wishbone byte address, word-aligned):
--   0x00  CONTROL     W   [1:0] opcode: 0=nop, 1=FILL (write triggers start)
--   0x04  STATUS      R   [0] busy
--   0x08  DST_ADDR    R/W [31:0] destination byte address (absolute)
--   0x0C  WIDTH       R/W [15:0] pixels per row
--   0x10  HEIGHT      R/W [15:0] number of rows
--   0x14  DST_STRIDE  R/W [15:0] destination row stride (bytes)
--   0x18  COLOR       R/W [15:0] RGB565 fill color

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gpu_2d is
    port (
        clk_50m_i    : in  std_logic;
        clk_100m_i   : in  std_logic;
        rst_n_i      : in  std_logic;

        -- Wishbone register interface (50MHz)
        reg_adr_i    : in  std_logic_vector(15 downto 0);
        reg_dat_i    : in  std_logic_vector(31 downto 0);
        reg_dat_o    : out std_logic_vector(31 downto 0);
        reg_we_i     : in  std_logic;
        reg_stb_i    : in  std_logic;
        reg_ack_o    : out std_logic;

        -- SDRAM burst-write interface (100MHz)
        gpu_wr_adr_o   : out std_logic_vector(24 downto 0);
        gpu_wr_dat_o   : out std_logic_vector(31 downto 0);
        gpu_wr_req_o   : out std_logic;
        gpu_wr_done_i  : in  std_logic
    );
end entity gpu_2d;

architecture rtl of gpu_2d is

    constant BURST_WORDS : integer := 8;  -- 8 words per burst = 16 pixels

    -- Registers (50MHz domain)
    signal reg_dst_addr  : unsigned(31 downto 0);
    signal reg_width     : unsigned(15 downto 0);
    signal reg_height    : unsigned(15 downto 0);
    signal reg_stride    : unsigned(15 downto 0);
    signal reg_color     : std_logic_vector(15 downto 0);
    signal reg_ack_ff    : std_logic;

    -- CDC: start trigger (50MHz → 100MHz)
    signal start_toggle  : std_logic;
    signal start_sync    : std_logic_vector(2 downto 0);
    signal start_seen    : std_logic;
    signal start_fire    : std_logic;

    -- CDC: busy flag (100MHz → 50MHz)
    signal busy_100m     : std_logic;
    signal busy_sync     : std_logic_vector(2 downto 0);

    -- Shadow registers latched at start (100MHz domain)
    signal shadow_base   : unsigned(24 downto 0);
    signal shadow_width  : unsigned(15 downto 0);  -- pixels
    signal shadow_height : unsigned(15 downto 0);
    signal shadow_stride : unsigned(15 downto 0);  -- bytes
    signal shadow_color  : std_logic_vector(31 downto 0);

    -- FSM (100MHz domain)
    type gpu_state_t is (
        G_IDLE,
        G_ROW_SETUP,
        G_BURST_REQ,
        G_BURST_WAIT,
        G_BURST_NEXT,
        G_ROW_NEXT
    );
    signal gpu_state     : gpu_state_t;

    signal cur_row       : unsigned(15 downto 0);
    signal cur_col_px    : unsigned(15 downto 0);  -- pixels remaining in row
    signal cur_addr      : unsigned(24 downto 0);  -- current SDRAM word address

begin

    -- ================================================================
    -- Wishbone register interface (50MHz)
    -- ================================================================
    p_reg : process(clk_50m_i, rst_n_i)
        variable adr : integer;
    begin
        if rst_n_i = '0' then
            reg_dst_addr <= (others => '0');
            reg_width    <= (others => '0');
            reg_height   <= (others => '0');
            reg_stride   <= (others => '0');
            reg_color    <= (others => '0');
            start_toggle <= '0';
            reg_ack_ff   <= '0';
        elsif rising_edge(clk_50m_i) then
            reg_ack_ff   <= '0';
            start_toggle <= '0';

            if reg_stb_i = '1' and reg_ack_ff = '0' then
                reg_ack_ff <= '1';
                adr := to_integer(unsigned(reg_adr_i(15 downto 2)));

                if reg_we_i = '1' then
                    case adr is
                        when 0 =>
                            if reg_dat_i(1 downto 0) = "01" then
                                start_toggle <= '1';
                            end if;
                        when 2 => reg_dst_addr <= unsigned(reg_dat_i);
                        when 3 => reg_width    <= unsigned(reg_dat_i(15 downto 0));
                        when 4 => reg_height   <= unsigned(reg_dat_i(15 downto 0));
                        when 5 => reg_stride   <= unsigned(reg_dat_i(15 downto 0));
                        when 6 => reg_color    <= reg_dat_i(15 downto 0);
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    reg_ack_o <= reg_ack_ff;

    -- Register read (combinational)
    p_reg_rd : process(reg_adr_i, reg_dst_addr, reg_width, reg_height,
                       reg_stride, reg_color, busy_sync)
        variable adr : integer;
    begin
        reg_dat_o <= (others => '0');
        adr := to_integer(unsigned(reg_adr_i(15 downto 2)));
        case adr is
            when 1 => reg_dat_o(0) <= busy_sync(2);
            when 2 => reg_dat_o <= std_logic_vector(reg_dst_addr);
            when 3 => reg_dat_o(15 downto 0) <= std_logic_vector(reg_width);
            when 4 => reg_dat_o(15 downto 0) <= std_logic_vector(reg_height);
            when 5 => reg_dat_o(15 downto 0) <= std_logic_vector(reg_stride);
            when 6 => reg_dat_o(15 downto 0) <= reg_color;
            when others => null;
        end case;
    end process;

    -- ================================================================
    -- CDC: start (50MHz → 100MHz) and busy (100MHz → 50MHz)
    -- ================================================================
    p_cdc_start : process(clk_100m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            start_sync <= (others => '0');
            start_seen <= '0';
        elsif rising_edge(clk_100m_i) then
            start_sync <= start_sync(1 downto 0) & start_toggle;
            start_seen <= start_sync(2);
        end if;
    end process;
    start_fire <= start_sync(2) xor start_seen;

    p_cdc_busy : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            busy_sync <= (others => '0');
        elsif rising_edge(clk_50m_i) then
            busy_sync <= busy_sync(1 downto 0) & busy_100m;
        end if;
    end process;

    -- ================================================================
    -- Rendering FSM (100MHz domain)
    -- ================================================================
    -- Byte address to word address: word_addr = byte_addr(31 downto 2)
    -- Stride in words = stride_bytes / 4
    -- Width in words = width_pixels / 2 (2 pixels per word)

    gpu_wr_dat_o <= shadow_color;

    p_gpu_fsm : process(clk_100m_i, rst_n_i)
        variable word_stride : unsigned(15 downto 0);
        variable burst_px    : integer;
    begin
        if rst_n_i = '0' then
            gpu_state     <= G_IDLE;
            busy_100m     <= '0';
            gpu_wr_req_o  <= '0';
            gpu_wr_adr_o  <= (others => '0');
            shadow_base   <= (others => '0');
            shadow_width  <= (others => '0');
            shadow_height <= (others => '0');
            shadow_stride <= (others => '0');
            shadow_color  <= (others => '0');
            cur_row       <= (others => '0');
            cur_col_px    <= (others => '0');
            cur_addr      <= (others => '0');
        elsif rising_edge(clk_100m_i) then
            gpu_wr_req_o <= '0';

            case gpu_state is

                when G_IDLE =>
                    busy_100m <= '0';
                    if start_fire = '1' then
                        -- Latch registers
                        shadow_base   <= reg_dst_addr(24 downto 0);
                        shadow_width  <= reg_width;
                        shadow_height <= reg_height;
                        shadow_stride <= reg_stride;
                        shadow_color  <= reg_color & reg_color;
                        cur_row       <= reg_height;
                        cur_addr      <= reg_dst_addr(26 downto 2);
                        busy_100m     <= '1';
                        gpu_state     <= G_ROW_SETUP;
                    end if;

                when G_ROW_SETUP =>
                    if cur_row = 0 then
                        gpu_state <= G_IDLE;
                    else
                        cur_col_px <= shadow_width;
                        gpu_state  <= G_BURST_REQ;
                    end if;

                when G_BURST_REQ =>
                    gpu_wr_adr_o <= std_logic_vector(cur_addr);
                    gpu_wr_req_o <= '1';
                    gpu_state    <= G_BURST_WAIT;

                when G_BURST_WAIT =>
                    if gpu_wr_done_i = '1' then
                        -- 8 words written = 16 pixels
                        cur_addr   <= cur_addr + BURST_WORDS;
                        if cur_col_px > 16 then
                            cur_col_px <= cur_col_px - 16;
                            gpu_state  <= G_BURST_REQ;
                        else
                            gpu_state <= G_ROW_NEXT;
                        end if;
                    end if;

                when G_ROW_NEXT =>
                    cur_row <= cur_row - 1;
                    -- Advance to next row: addr += stride_in_words - width_in_words
                    word_stride := resize(shadow_stride(15 downto 2), 16);
                    cur_addr <= cur_addr + resize(word_stride, 25) -
                                resize(shadow_width(15 downto 1), 25);
                    gpu_state <= G_ROW_SETUP;

                when others =>
                    gpu_state <= G_IDLE;

            end case;
        end if;
    end process;

end architecture rtl;
