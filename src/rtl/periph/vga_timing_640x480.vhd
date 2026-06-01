-- vga_timing_640x480.vhd -- 640x480@60Hz VGA timing core
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_timing_640x480 is
    port (
        clk_25m_i    : in  std_logic;
        rst_n_i      : in  std_logic;
        h_count_o    : out unsigned(9 downto 0);
        v_count_o    : out unsigned(9 downto 0);
        active_x_o   : out unsigned(9 downto 0);
        active_y_o   : out unsigned(8 downto 0);
        line_index_o : out unsigned(8 downto 0);
        video_on_o   : out std_logic;
        line_start_o : out std_logic;
        hs_o         : out std_logic;
        vs_o         : out std_logic;
        blank_o      : out std_logic;
        sync_o       : out std_logic
    );
end entity vga_timing_640x480;

architecture rtl of vga_timing_640x480 is

    constant H_TOTAL  : integer := 800;
    constant H_SYNC   : integer := 96;
    constant H_BP     : integer := 48;
    constant H_ACTIVE : integer := 640;
    constant V_TOTAL  : integer := 525;
    constant V_SYNC   : integer := 2;
    constant V_BP     : integer := 33;
    constant V_ACTIVE : integer := 480;

    signal h_count  : integer range 0 to H_TOTAL - 1;
    signal v_count  : integer range 0 to V_TOTAL - 1;
    signal active_line : std_logic;
    signal video_on : std_logic;

begin

    p_timing : process(clk_25m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            h_count <= 0;
            v_count <= 0;
        elsif rising_edge(clk_25m_i) then
            if h_count = H_TOTAL - 1 then
                h_count <= 0;
                if v_count = V_TOTAL - 1 then
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
                end if;
            else
                h_count <= h_count + 1;
            end if;
        end if;
    end process;

    active_line <= '1' when
        v_count >= (V_SYNC + V_BP) and v_count < (V_SYNC + V_BP + V_ACTIVE)
        else '0';

    video_on <= '1' when
        h_count >= (H_SYNC + H_BP) and h_count < (H_SYNC + H_BP + H_ACTIVE) and
        active_line = '1'
        else '0';

    h_count_o <= to_unsigned(h_count, h_count_o'length);
    v_count_o <= to_unsigned(v_count, v_count_o'length);
    active_x_o <= to_unsigned(h_count - (H_SYNC + H_BP), active_x_o'length)
                  when video_on = '1' else (others => '0');
    active_y_o <= to_unsigned(v_count - (V_SYNC + V_BP), active_y_o'length)
                  when video_on = '1' else (others => '0');
    line_index_o <= to_unsigned(v_count - (V_SYNC + V_BP), line_index_o'length)
                    when active_line = '1' else (others => '0');
    line_start_o <= '1' when
        h_count = 0 and
        active_line = '1'
        else '0';

    hs_o    <= '0' when h_count < H_SYNC else '1';
    vs_o    <= '0' when v_count < V_SYNC else '1';
    blank_o <= video_on;
    sync_o  <= '0' when (h_count >= H_SYNC and v_count >= V_SYNC) else '1';
    video_on_o <= video_on;

end architecture rtl;
