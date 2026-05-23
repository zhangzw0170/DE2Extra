-- pong_engine.vhd — Hardware PONG game engine with VGA pixel output
--
-- 640×480 playfield, 8×8 ball, 8×40 paddles, 60fps physics.
-- CPU writes paddle positions (from PS/2), reads scores.
-- VGA pixel output is fully hardware: no frame buffer needed.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity pong_engine is
    port (
        clk_i        : in  std_logic;
        rst_n_i      : in  std_logic;

        -- VGA timing inputs (for pixel rendering)
        h_count_i    : in  integer range 0 to 799;
        v_count_i    : in  integer range 0 to 524;
        video_on_i   : in  std_logic;

        -- Paddle control (from CPU/PS2)
        paddle_l_i   : in  integer range 0 to 439;  -- left paddle top Y (0-439, 40px tall)
        paddle_r_i   : in  integer range 0 to 439;  -- right paddle top Y

        -- Game control
        serve_i      : in  std_logic;   -- restart ball from center
        pause_i      : in  std_logic;

        -- Score output
        score_l_o    : out integer range 0 to 9;
        score_r_o    : out integer range 0 to 9;

        -- VGA pixel output
        pixel_r_o    : out std_logic_vector(7 downto 0);
        pixel_g_o    : out std_logic_vector(7 downto 0);
        pixel_b_o    : out std_logic_vector(7 downto 0)
    );
end pong_engine;

architecture rtl of pong_engine is

    -- Playfield constants
    constant FIELD_W   : integer := 640;
    constant FIELD_H   : integer := 480;
    constant PADDLE_W  : integer := 8;
    constant PADDLE_H  : integer := 40;
    constant BALL_SIZE : integer := 8;

    -- Ball state
    signal ball_x     : integer range -16 to FIELD_W + 16 := FIELD_W / 2;
    signal ball_y     : integer range -16 to FIELD_H + 16 := FIELD_H / 2;
    signal ball_vx    : integer range -4 to 4 := 2;
    signal ball_vy    : integer range -4 to 4 := 1;

    -- Scores
    signal score_l    : integer range 0 to 9 := 0;
    signal score_r    : integer range 0 to 9 := 0;

    -- Frame counter (ball moves once per vsync)
    signal vs_prev    : std_logic := '0';

    -- Pixel generation signals
    signal pixel_x    : integer range 0 to 639;
    signal pixel_y    : integer range 0 to 479;

    -- Dash pattern for center line
    signal dash_on    : std_logic;

begin

    pixel_x <= h_count_i - 144;  -- after sync + back porch
    pixel_y <= v_count_i - 34;

    -- ═══════════════════════════════════════════════════════════
    -- Game physics (runs once per frame on vsync falling edge)
    -- ═══════════════════════════════════════════════════════════
    process(clk_i)
        variable new_ball_y : integer;
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                ball_x  <= FIELD_W / 2;
                ball_y  <= FIELD_H / 2;
                ball_vx <= 2;
                ball_vy <= 1;
                score_l <= 0;
                score_r <= 0;
            else
                vs_prev <= v_count_i;

                -- Serve
                if serve_i = '1' then
                    ball_x     <= FIELD_W / 2;
                    ball_y     <= FIELD_H / 2;
                    ball_vx    <= 2;
                    ball_vy    <= 1;
                end if;

                -- Physics update on vsync falling edge (end of frame)
                if vs_prev > 512 and v_count_i < 10 and pause_i = '0' then
                    if ball_x < -BALL_SIZE then
                        -- Left scores
                        score_r <= score_r + 1;
                        ball_x  <= FIELD_W / 2;
                        ball_y  <= FIELD_H / 2;
                        ball_vx <=  2;
                        ball_vy <=  1;
                    elsif ball_x > FIELD_W + BALL_SIZE then
                        -- Right scores
                        score_l <= score_l + 1;
                        ball_x  <= FIELD_W / 2;
                        ball_y  <= FIELD_H / 2;
                        ball_vx <= -2;
                        ball_vy <=  1;
                    else
                        -- Move ball
                        new_ball_y := ball_y + ball_vy;

                        -- Top/bottom wall bounce
                        if new_ball_y < 0 then
                            new_ball_y := 0;
                            ball_vy    <= -ball_vy;
                        elsif new_ball_y + BALL_SIZE > FIELD_H - 1 then
                            new_ball_y := FIELD_H - BALL_SIZE;
                            ball_vy    <= -ball_vy;
                        end if;
                        ball_y <= new_ball_y;

                        -- Left paddle collision
                        if ball_vx < 0 and ball_x <= PADDLE_W + 4 and ball_x >= PADDLE_W - 4 then
                            if (ball_y + BALL_SIZE > paddle_l_i) and
                               (ball_y < paddle_l_i + PADDLE_H) then
                                ball_vx <= -ball_vx;
                                ball_x  <= PADDLE_W + 1;
                            end if;
                        end if;

                        -- Right paddle collision
                        if ball_vx > 0 and
                           ball_x + BALL_SIZE >= FIELD_W - PADDLE_W - 4 and
                           ball_x + BALL_SIZE <= FIELD_W - PADDLE_W + 4 then
                            if (ball_y + BALL_SIZE > paddle_r_i) and
                               (ball_y < paddle_r_i + PADDLE_H) then
                                ball_vx <= -ball_vx;
                                ball_x  <= FIELD_W - PADDLE_W - BALL_SIZE - 1;
                            end if;
                        end if;

                        ball_x <= ball_x + ball_vx;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ═══════════════════════════════════════════════════════════
    -- Score output
    -- ═══════════════════════════════════════════════════════════
    score_l_o <= score_l;
    score_r_o <= score_r;

    -- ═══════════════════════════════════════════════════════════
    -- Center dash line pattern
    -- ═══════════════════════════════════════════════════════════
    dash_on <= '1' when (pixel_y / 16) mod 2 = 0 else '0';

    -- ═══════════════════════════════════════════════════════════
    -- Pixel rendering (combinatorial)
    -- ═══════════════════════════════════════════════════════════
    process(clk_i)
        variable is_ball   : boolean;
        variable is_pad_l  : boolean;
        variable is_pad_r  : boolean;
        variable is_center : boolean;
        variable is_top    : boolean;
        variable is_bottom : boolean;
    begin
        if rising_edge(clk_i) then
            if video_on_i = '0' then
                pixel_r_o <= x"00";
                pixel_g_o <= x"00";
                pixel_b_o <= x"00";
            else
                -- Hit test all objects
                is_ball := (pixel_x >= ball_x) and
                           (pixel_x < ball_x + BALL_SIZE) and
                           (pixel_y >= ball_y) and
                           (pixel_y < ball_y + BALL_SIZE);

                is_pad_l := (pixel_x < PADDLE_W) and
                            (pixel_y >= paddle_l_i) and
                            (pixel_y < paddle_l_i + PADDLE_H);

                is_pad_r := (pixel_x >= FIELD_W - PADDLE_W) and
                            (pixel_x < FIELD_W) and
                            (pixel_y >= paddle_r_i) and
                            (pixel_y < paddle_r_i + PADDLE_H);

                is_center := (pixel_x >= 318) and (pixel_x <= 321) and dash_on = '1';
                is_top    := (pixel_y < 2);
                is_bottom := (pixel_y >= FIELD_H - 2);

                if is_ball then
                    pixel_r_o <= x"FF"; pixel_g_o <= x"FF"; pixel_b_o <= x"00";  -- yellow
                elsif is_pad_l then
                    pixel_r_o <= x"00"; pixel_g_o <= x"FF"; pixel_b_o <= x"FF";  -- cyan
                elsif is_pad_r then
                    pixel_r_o <= x"FF"; pixel_g_o <= x"00"; pixel_b_o <= x"FF";  -- magenta
                elsif is_center then
                    pixel_r_o <= x"80"; pixel_g_o <= x"80"; pixel_b_o <= x"80";  -- gray dashed
                elsif is_top or is_bottom then
                    pixel_r_o <= x"FF"; pixel_g_o <= x"FF"; pixel_b_o <= x"FF";  -- white walls
                else
                    pixel_r_o <= x"00"; pixel_g_o <= x"10"; pixel_b_o <= x"20";  -- dark blue bg
                end if;
            end if;
        end if;
    end process;

end rtl;
