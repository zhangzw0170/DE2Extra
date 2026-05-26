-- pong_engine.vhd — Hardware PONG game engine with VGA output
--
-- 640x480 playfield, 8x8 ball, 8x40 paddles.
-- Self-contained VGA timing generator (25MHz pixel clock from 50MHz divider).
-- Wishbone slave for CPU control (paddle positions, scores).
--
-- Slave registers (word-aligned, 4-byte stride):
--   0x00 [W] paddle_l: bits[8:0] = top Y position (0..439)
--   0x04 [W] paddle_r: bits[8:0] = top Y position
--   0x08 [W] control: bit0=reset/serve, bit1=pause
--   0x0C [R] scores: [15:8]=left, [7:0]=right (0..9 each)
--
-- VGA outputs directly drive display (no framebuffer needed).
-- A top-level MUX selects between pong VGA and text terminal VGA.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pong_engine is
    port (
        clk_50m_i   : in  std_logic;
        rst_n_i     : in  std_logic;

        -- Wishbone slave (CPU control)
        wb_adr_i    : in  std_logic_vector(4 downto 0);
        wb_dat_i    : in  std_logic_vector(31 downto 0);
        wb_dat_o    : out std_logic_vector(31 downto 0);
        wb_we_i     : in  std_logic;
        wb_stb_i    : in  std_logic;
        wb_ack_o    : out std_logic;

        -- VGA outputs (direct pixel generation)
        vga_r_o     : out std_logic_vector(7 downto 0);
        vga_g_o     : out std_logic_vector(7 downto 0);
        vga_b_o     : out std_logic_vector(7 downto 0);
        vga_hs_o    : out std_logic;
        vga_vs_o    : out std_logic;
        vga_blank_o : out std_logic;
        vga_sync_o  : out std_logic;
        vga_clk_o   : out std_logic;
        vga_en_o    : out std_logic   -- '1' = pong active, top-level MUX uses this
    );
end entity pong_engine;

architecture rtl of pong_engine is

    -- VGA 640x480 @ 60Hz timing
    constant H_TOTAL   : integer := 800;
    constant H_SYNC    : integer := 96;
    constant H_BP      : integer := 48;
    constant H_ACTIVE  : integer := 640;
    constant V_TOTAL   : integer := 525;
    constant V_SYNC    : integer := 2;
    constant V_BP      : integer := 33;
    constant V_ACTIVE  : integer := 480;

    -- Game objects
    constant PADDLE_W  : integer := 8;
    constant PADDLE_H  : integer := 40;
    constant BALL_SIZE : integer := 8;

    -- VGA counters
    signal h_count  : integer range 0 to H_TOTAL - 1 := 0;
    signal v_count  : integer range 0 to V_TOTAL - 1 := 0;
    signal pixel_x  : integer range 0 to H_ACTIVE - 1 := 0;
    signal pixel_y  : integer range 0 to V_ACTIVE - 1 := 0;
    signal video_on : std_logic;

    -- 25MHz pixel clock divider
    signal clk_25m  : std_logic := '0';
    signal clk_25m_r : std_logic := '0';

    -- Paddle positions (CPU writes)
    signal paddle_l  : integer range 0 to V_ACTIVE - PADDLE_H := 220;
    signal paddle_r  : integer range 0 to V_ACTIVE - PADDLE_H := 220;

    -- Ball state
    signal ball_x    : integer range 0 to H_ACTIVE - 1 := H_ACTIVE / 2;
    signal ball_y    : integer range 0 to V_ACTIVE - BALL_SIZE := V_ACTIVE / 2 - 4;
    signal ball_vx   : integer range -3 to 3 := 2;
    signal ball_vy   : integer range -3 to 3 := 1;

    -- Scores
    signal score_l   : integer range 0 to 9 := 0;
    signal score_r   : integer range 0 to 9 := 0;

    -- Control
    signal paused    : std_logic := '0';

    -- Frame sync: detect end of frame for physics update
    signal vsync_d  : integer range 0 to V_TOTAL - 1 := 0;

    -- Enable
    signal enabled  : std_logic := '0';

begin

    -- ================================================================
    -- 25MHz pixel clock
    -- ================================================================
    process(clk_50m_i)
    begin
        if rising_edge(clk_50m_i) then
            clk_25m <= not clk_25m;
        end if;
    end process;
    vga_clk_o <= clk_25m;

    -- Double-flop for metastability
    process(clk_50m_i)
    begin
        if rising_edge(clk_50m_i) then
            clk_25m_r <= clk_25m;
        end if;
    end process;

    -- ================================================================
    -- VGA Timing Generator (25MHz domain)
    -- ================================================================
    process(clk_25m)
    begin
        if rising_edge(clk_25m) then
            -- Horizontal
            if h_count = H_TOTAL - 1 then
                h_count <= 0;
            else
                h_count <= h_count + 1;
            end if;

            -- Vertical
            if h_count = H_TOTAL - 1 then
                if v_count = V_TOTAL - 1 then
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
                end if;
            end if;

            -- Sync signals
            if h_count < H_SYNC then
                vga_hs_o <= '0';
            else
                vga_hs_o <= '1';
            end if;

            if v_count < V_SYNC then
                vga_vs_o <= '0';
            else
                vga_vs_o <= '1';
            end if;

            if (h_count >= H_SYNC + H_BP) and
               (h_count < H_SYNC + H_BP + H_ACTIVE) and
               (v_count >= V_SYNC + V_BP) and
               (v_count < V_SYNC + V_BP + V_ACTIVE) then
                vga_blank_o <= '0';
                video_on    <= '1';
            else
                vga_blank_o <= '1';
                video_on    <= '0';
            end if;

            if (h_count < H_SYNC) or (v_count < V_SYNC) then
                vga_sync_o <= '1';
            else
                vga_sync_o <= '0';
            end if;

            -- Pixel coordinates (within active region)
            if h_count >= H_SYNC + H_BP and h_count < H_SYNC + H_BP + H_ACTIVE then
                pixel_x <= h_count - (H_SYNC + H_BP);
            else
                pixel_x <= 0;
            end if;
            if v_count >= V_SYNC + V_BP and v_count < V_SYNC + V_BP + V_ACTIVE then
                pixel_y <= v_count - (V_SYNC + V_BP);
            else
                pixel_y <= 0;
            end if;
        end if;
    end process;

    -- ================================================================
    -- Wishbone Slave + Game Physics (merged, 50MHz domain)
    -- ================================================================
    process(clk_50m_i)
        variable addr : integer range 0 to 7;
        variable v_serve_req : std_logic;
        variable new_x : integer range 0 to H_ACTIVE - 1;
        variable new_y : integer range 0 to V_ACTIVE - BALL_SIZE;
    begin
        if rising_edge(clk_50m_i) then
            if rst_n_i = '0' then
                paddle_l <= 220;
                paddle_r <= 220;
                paused <= '0';
                enabled <= '0';
                ball_x <= H_ACTIVE / 2;
                ball_y <= V_ACTIVE / 2 - 4;
                ball_vx <= 2;
                ball_vy <= 1;
                score_l <= 0;
                score_r <= 0;
                wb_dat_o <= (others => '0');
                wb_ack_o <= '0';
            else
                -- Defaults
                wb_ack_o <= '0';
                wb_dat_o <= (others => '0');

                v_serve_req := '0';

                -- WB slave
                if wb_stb_i = '1' then
                    wb_ack_o <= '1';
                    addr := to_integer(unsigned(wb_adr_i(4 downto 2)));

                    if wb_we_i = '1' then
                        case addr is
                            when 0 =>  -- paddle_l
                                if to_integer(unsigned(wb_dat_i(9 downto 0))) < V_ACTIVE - PADDLE_H then
                                    paddle_l <= to_integer(unsigned(wb_dat_i(9 downto 0)));
                                end if;
                            when 1 =>  -- paddle_r
                                if to_integer(unsigned(wb_dat_i(9 downto 0))) < V_ACTIVE - PADDLE_H then
                                    paddle_r <= to_integer(unsigned(wb_dat_i(9 downto 0)));
                                end if;
                            when 2 =>  -- control
                                if wb_dat_i(0) = '1' then
                                    v_serve_req := '1';
                                end if;
                                paused <= wb_dat_i(1);
                                enabled <= wb_dat_i(2);
                            when others => null;
                        end case;
                    else
                        case addr is
                            when 3 =>  -- scores
                                wb_dat_o(15 downto 8) <= std_logic_vector(to_unsigned(score_l, 8));
                                wb_dat_o(7 downto 0) <= std_logic_vector(to_unsigned(score_r, 8));
                            when others => null;
                        end case;
                    end if;
                end if;

                -- Physics
                vsync_d <= v_count;

                if enabled = '0' then
                    null;
                elsif v_serve_req = '1' then
                    ball_x <= H_ACTIVE / 2;
                    ball_y <= V_ACTIVE / 2 - 4;
                    ball_vx <= 2;
                    ball_vy <= 1;
                else
                    if vsync_d >= (V_TOTAL - 10) and v_count < 10 and paused = '0' then
                        if ball_x + BALL_SIZE < PADDLE_W then
                            score_r <= score_r + 1;
                            ball_x <= H_ACTIVE / 2;
                            ball_y <= V_ACTIVE / 2 - 4;
                            ball_vx <= 2;
                            ball_vy <= 1;
                        elsif ball_x >= H_ACTIVE - PADDLE_W then
                            score_l <= score_l + 1;
                            ball_x <= H_ACTIVE / 2;
                            ball_y <= V_ACTIVE / 2 - 4;
                            ball_vx <= -2;
                            ball_vy <= 1;
                        else
                            new_y := ball_y + ball_vy;
                            if new_y < 0 then
                                new_y := 0;
                                ball_vy <= -ball_vy;
                            elsif new_y + BALL_SIZE > V_ACTIVE - 1 then
                                new_y := V_ACTIVE - BALL_SIZE;
                                ball_vy <= -ball_vy;
                            end if;
                            ball_y <= new_y;

                            new_x := ball_x + ball_vx;

                            if ball_vx < 0 and new_x <= PADDLE_W and ball_x > PADDLE_W then
                                if (ball_y + BALL_SIZE > paddle_l) and
                                   (ball_y < paddle_l + PADDLE_H) then
                                    ball_vx <= -ball_vx;
                                    new_x := PADDLE_W + 1;
                                end if;
                            end if;

                            if ball_vx > 0 and new_x + BALL_SIZE >= H_ACTIVE - PADDLE_W and
                               ball_x + BALL_SIZE < H_ACTIVE - PADDLE_W then
                                if (ball_y + BALL_SIZE > paddle_r) and
                                   (ball_y < paddle_r + PADDLE_H) then
                                    ball_vx <= -ball_vx;
                                    new_x := H_ACTIVE - PADDLE_W - BALL_SIZE - 1;
                                end if;
                            end if;

                            ball_x <= new_x;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    vga_en_o <= enabled;

    -- ================================================================
    -- Pixel Rendering (combinatorial in 25MHz domain)
    -- ================================================================
    process(clk_25m)
        variable is_ball   : boolean;
        variable is_pad_l  : boolean;
        variable is_pad_r  : boolean;
        variable is_dash   : boolean;
        variable is_wall   : boolean;
    begin
        if rising_edge(clk_25m) then
            if video_on = '0' then
                vga_r_o <= x"00";
                vga_g_o <= x"10";
                vga_b_o <= x"20";
            else
                is_ball  := (pixel_x >= ball_x) and (pixel_x < ball_x + BALL_SIZE) and
                            (pixel_y >= ball_y) and (pixel_y < ball_y + BALL_SIZE);

                is_pad_l := (pixel_x < PADDLE_W) and
                             (pixel_y >= paddle_l) and (pixel_y < paddle_l + PADDLE_H);

                is_pad_r := (pixel_x >= H_ACTIVE - PADDLE_W) and (pixel_x < H_ACTIVE) and
                             (pixel_y >= paddle_r) and (pixel_y < paddle_r + PADDLE_H);

                is_dash  := (pixel_x >= 318) and (pixel_x <= 321) and
                             ((pixel_y / 16) mod 2 = 0);

                is_wall  := (pixel_y < 2) or (pixel_y >= V_ACTIVE - 2);

                if is_ball then
                    vga_r_o <= x"FF"; vga_g_o <= x"FF"; vga_b_o <= x"00";  -- yellow
                elsif is_pad_l then
                    vga_r_o <= x"00"; vga_g_o <= x"FF"; vga_b_o <= x"FF";  -- cyan
                elsif is_pad_r then
                    vga_r_o <= x"FF"; vga_g_o <= x"00"; vga_b_o <= x"FF";  -- magenta
                elsif is_dash then
                    vga_r_o <= x"60"; vga_g_o <= x"60"; vga_b_o <= x"60";  -- gray dash
                elsif is_wall then
                    vga_r_o <= x"FF"; vga_g_o <= x"FF"; vga_b_o <= x"FF";  -- white
                else
                    vga_r_o <= x"00"; vga_g_o <= x"10"; vga_b_o <= x"20";  -- dark bg
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
