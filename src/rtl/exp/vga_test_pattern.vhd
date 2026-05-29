-- vga_test_pattern.vhd — VGA 640x480@60Hz test pattern generator
--
-- Generates standard VGA sync timing from 50 MHz clock (pixel clock = 25 MHz).
-- Supports 8 pattern modes and optional horizontal animation.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_test_pattern is
    port (
        clk_50m_i   : in  std_logic;
        rst_n_i     : in  std_logic;

        -- Pattern control
        mode_i      : in  std_logic_vector(2 downto 0);
        animate_i   : in  std_logic;
        speed_i     : in  std_logic_vector(3 downto 0);

        -- VGA output
        vga_r_o     : out std_logic_vector(7 downto 0);
        vga_g_o     : out std_logic_vector(7 downto 0);
        vga_b_o     : out std_logic_vector(7 downto 0);
        vga_hs_o    : out std_logic;
        vga_vs_o    : out std_logic;
        vga_clk_o   : out std_logic;
        vga_blank_o : out std_logic;
        vga_sync_o  : out std_logic;

        -- Debug
        hc_o        : out std_logic_vector(9 downto 0);
        vc_o        : out std_logic_vector(9 downto 0);
        frame_o     : out std_logic
    );
end entity vga_test_pattern;

architecture rtl of vga_test_pattern is

    -- 640x480@60Hz timing (pixel clock domain, 25 MHz)
    constant H_VIS      : integer := 640;
    constant H_SYNC_S   : integer := 656;   -- 640 + 16 FP
    constant H_SYNC_E   : integer := 752;   -- 656 + 96 sync
    constant H_TOTAL    : integer := 800;

    constant V_VIS      : integer := 480;
    constant V_SYNC_S   : integer := 490;   -- 480 + 10 FP
    constant V_SYNC_E   : integer := 492;   -- 490 + 2 sync
    constant V_TOTAL    : integer := 525;

    signal pix_div   : std_logic;
    signal hc        : integer range 0 to H_TOTAL - 1;
    signal vc        : integer range 0 to V_TOTAL - 1;
    signal frame_reg : std_logic;

    -- Animation: horizontal pixel offset (wraps at 640)
    signal shift_reg : unsigned(9 downto 0);

    -- Effective horizontal pixel (after animation shift)
    signal hp : unsigned(9 downto 0);

    -- Bar index 0..7 for vertical bars
    signal bar : integer range 0 to 7;

begin

    vga_clk_o  <= pix_div;
    vga_sync_o <= '0';

    -- Sync signals (active-low sync pulses)
    vga_hs_o    <= '0' when hc >= H_SYNC_S and hc < H_SYNC_E else '1';
    vga_vs_o    <= '0' when vc >= V_SYNC_S and vc < V_SYNC_E else '1';
    vga_blank_o <= '1' when hc < H_VIS and vc < V_VIS else '0';

    -- 25 MHz pixel clock divider + timing counters
    p_timing : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            pix_div   <= '0';
            hc        <= 0;
            vc        <= 0;
            frame_reg <= '0';
        elsif rising_edge(clk_50m_i) then
            pix_div   <= not pix_div;
            frame_reg <= '0';

            -- Advance pixel counters on falling edge of pix_div
            if pix_div = '1' then
                if hc = H_TOTAL - 1 then
                    hc <= 0;
                    if vc = V_TOTAL - 1 then
                        vc <= 0;
                        frame_reg <= '1';
                    else
                        vc <= vc + 1;
                    end if;
                else
                    hc <= hc + 1;
                end if;
            end if;
        end if;
    end process;

    hc_o <= std_logic_vector(to_unsigned(hc, 10));
    vc_o <= std_logic_vector(to_unsigned(vc, 10));
    frame_o <= frame_reg;

    -- Animation shift: increments each frame
    p_shift : process(clk_50m_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            shift_reg <= (others => '0');
        elsif rising_edge(clk_50m_i) then
            if frame_reg = '1' and animate_i = '1' then
                shift_reg <= shift_reg + unsigned(speed_i);
            end if;
        end if;
    end process;

    -- Effective horizontal pixel with wrap-around
    p_hp : process(hc, shift_reg)
        variable raw : unsigned(10 downto 0);
    begin
        if hc < H_VIS then
            raw := resize(shift_reg, 11) + to_unsigned(hc, 11);
            if raw >= 640 then
                hp <= raw(9 downto 0) - to_unsigned(640, 10);
            else
                hp <= raw(9 downto 0);
            end if;
        else
            hp <= (others => '0');
        end if;
    end process;

    -- Bar index: 0..7 (each bar is 80 pixels wide)
    p_bar : process(hp)
    begin
        if    hp < 80  then bar <= 0;
        elsif hp < 160 then bar <= 1;
        elsif hp < 240 then bar <= 2;
        elsif hp < 320 then bar <= 3;
        elsif hp < 400 then bar <= 4;
        elsif hp < 480 then bar <= 5;
        elsif hp < 560 then bar <= 6;
        else                bar <= 7;
        end if;
    end process;

    -- Pattern generator (combinational, outputs 0 during blanking)
    p_pattern : process(mode_i, hp, vc, bar)
        variable vp : unsigned(9 downto 0);
        variable chk : std_logic;
    begin
        vga_r_o <= (others => '0');
        vga_g_o <= (others => '0');
        vga_b_o <= (others => '0');

        vp := to_unsigned(vc, 10);

        case mode_i is
            when "001" =>  -- 8-color vertical bars
                case bar is
                    when 0      => null;                                      -- black
                    when 1      => vga_b_o <= x"FF";                         -- blue
                    when 2      => vga_g_o <= x"FF";                         -- green
                    when 3      => vga_g_o <= x"FF"; vga_b_o <= x"FF";      -- cyan
                    when 4      => vga_r_o <= x"FF";                         -- red
                    when 5      => vga_r_o <= x"FF"; vga_b_o <= x"FF";      -- magenta
                    when 6      => vga_r_o <= x"FF"; vga_g_o <= x"FF";      -- yellow
                    when others => vga_r_o <= x"FF"; vga_g_o <= x"FF"; vga_b_o <= x"FF"; -- white
                end case;

            when "010" =>  -- 8-level gray ramp
                case bar is
                    when 0      => null;
                    when 1      => vga_r_o <= x"24"; vga_g_o <= x"24"; vga_b_o <= x"24";
                    when 2      => vga_r_o <= x"49"; vga_g_o <= x"49"; vga_b_o <= x"49";
                    when 3      => vga_r_o <= x"6D"; vga_g_o <= x"6D"; vga_b_o <= x"6D";
                    when 4      => vga_r_o <= x"92"; vga_g_o <= x"92"; vga_b_o <= x"92";
                    when 5      => vga_r_o <= x"B6"; vga_g_o <= x"B6"; vga_b_o <= x"B6";
                    when 6      => vga_r_o <= x"DB"; vga_g_o <= x"DB"; vga_b_o <= x"DB";
                    when others => vga_r_o <= x"FF"; vga_g_o <= x"FF"; vga_b_o <= x"FF";
                end case;

            when "011" =>  -- Checkerboard 8x8
                chk := hp(3) xor vp(3);
                if chk = '1' then
                    vga_r_o <= x"FF"; vga_g_o <= x"FF"; vga_b_o <= x"FF";
                end if;

            when "100" =>  -- Crosshatch grid (every 64 pixels)
                if (hp(5 downto 0) = "000000") or (vp(5 downto 0) = "000000") then
                    vga_r_o <= x"FF"; vga_g_o <= x"FF"; vga_b_o <= x"FF";
                end if;

            when "101" =>  -- Solid red
                vga_r_o <= x"FF";

            when "110" =>  -- Solid green
                vga_g_o <= x"FF";

            when "111" =>  -- All white
                vga_r_o <= x"FF"; vga_g_o <= x"FF"; vga_b_o <= x"FF";

            when others => null;  -- 000: black
        end case;
    end process;

end architecture rtl;
