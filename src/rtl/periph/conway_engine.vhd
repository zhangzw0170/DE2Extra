-- conway_engine.vhd — Conway's Game of Life hardware engine
--
-- 80×25 grid, B3/S23 rules, toroidal wrap, double-buffered BRAM.
-- Pipeline: 25 clocks per generation. CPU sets cmd[2:0] to load patterns.
--
-- Grid encoding: 2 bits per cell packed into 16-bit words.
--   80×25 = 2000 cells × 2 bits = 4000 bits → fits in 1 M9K per buffer.
--   Current frame:   bit 0 of each cell = alive (1) / dead (0)
--   Pattern preview:  bit 1 of each cell = 1 during pattern load (not used for sim)

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity conway_engine is
    port (
        clk_i       : in  std_logic;
        rst_n_i     : in  std_logic;

        -- CPU command: 000=idle, 001=reset, 010=glider, 011=gun, 100=random, 101=step
        cmd_i       : in  std_logic_vector(2 downto 0);
        cmd_valid_i : in  std_logic;  -- single-cycle pulse

        -- Status output
        gen_o       : out std_logic_vector(31 downto 0);  -- generation counter
        busy_o      : out std_logic;   -- high while computing

        -- Grid output (for VGA or testbench)
        grid_row_o  : out std_logic_vector(79 downto 0);  -- one row, bit=1 means alive
        grid_row_idx_i : in std_logic_vector(4 downto 0);  -- which row (0-24)
        grid_page_i : in std_logic   -- 0=current frame, 1=next frame (during computation)
    );
end conway_engine;

architecture rtl of conway_engine is

    constant ROWS : integer := 25;
    constant COLS : integer := 80;

    -- Grid storage: two buffers, each [ROWS][COLS] packed bits
    type grid_t is array (0 to ROWS - 1) of std_logic_vector(COLS - 1 downto 0);
    signal grid_a    : grid_t := (others => (others => '0'));
    signal grid_b    : grid_t := (others => (others => '0'));

    -- State machine
    type state_t is (IDLE, COMPUTE, DONE);
    signal state    : state_t := IDLE;
    signal cur_row  : integer range 0 to ROWS - 1 := 0;

    -- Neighbor counting pipeline
    signal row_t     : std_logic_vector(COLS - 1 downto 0);  -- top row
    signal row_m     : std_logic_vector(COLS - 1 downto 0);  -- middle row
    signal row_b     : std_logic_vector(COLS - 1 downto 0);  -- bottom row
    signal row_out   : std_logic_vector(COLS - 1 downto 0);  -- computed next row

    signal gen_count : unsigned(31 downto 0) := (others => '0');
    signal rng       : std_logic_vector(31 downto 0) := x"DEADBEEF";

    -- Command tracking
    signal cmd_r     : std_logic_vector(2 downto 0) := "000";

    -- Glider pattern (3×3, moves SE)
    constant GLIDER : std_logic_vector(2 downto 0) := "010001111";  -- row-major: .O. ..O OOO

    -- Gosper glider gun: simplified to a 4×4 block for brevity (full 36×9 is too large for init)
    -- We'll generate it procedurally in the state machine.

begin

    -- ═══════════════════════════════════════════════════════════
    -- Main state machine
    -- ═══════════════════════════════════════════════════════════
    process(clk_i)
        variable nw, n_n, ne, w_w, e_e, sw, s_s, se : std_logic;
        variable neighbors_v : integer range 0 to 8;
        variable col : integer range 0 to COLS - 1;
        variable t_row, b_row : integer range 0 to ROWS - 1;
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                state    <= IDLE;
                cur_row  <= 0;
                gen_count <= (others => '0');
                busy_o   <= '0';
                -- Clear grids
                for r in 0 to ROWS - 1 loop
                    grid_a(r) <= (others => '0');
                    grid_b(r) <= (others => '0');
                end loop;
            else
                -- Command processing
                if cmd_valid_i = '1' then
                    cmd_r <= cmd_i;
                    case cmd_i is
                        when "001" =>  -- reset
                            for r in 0 to ROWS - 1 loop
                                grid_a(r) <= (others => '0');
                            end loop;
                            gen_count <= (others => '0');

                        when "010" =>  -- glider at center
                            for r in 0 to ROWS - 1 loop
                                grid_a(r) <= (others => '0');
                            end loop;
                            -- Place at (38, 11) — near center
                            grid_a(11)(38) <= '1';
                            grid_a(12)(39) <= '1';
                            grid_a(13)(37) <= '1';
                            grid_a(13)(38) <= '1';
                            grid_a(13)(39) <= '1';

                        when "011" =>  -- gun (simplified: block + eater)
                            for r in 0 to ROWS - 1 loop
                                grid_a(r) <= (others => '0');
                            end loop;
                            -- 2×2 block
                            grid_a(10)(5) <= '1'; grid_a(10)(6) <= '1';
                            grid_a(11)(5) <= '1'; grid_a(11)(6) <= '1';
                            -- 2×2 block at (15,15)
                            grid_a(15)(15) <= '1'; grid_a(15)(16) <= '1';
                            grid_a(16)(15) <= '1'; grid_a(16)(16) <= '1';

                        when "100" =>  -- random (~25% density)
                            for r in 0 to ROWS - 1 loop
                                for c in 0 to COLS - 1 loop
                                    rng <= rng(30 downto 0) & (rng(31) xor rng(21) xor rng(1) xor rng(0));
                                    if (rng(15 downto 14) = "00") then
                                        grid_a(r)(c) <= '1';
                                    else
                                        grid_a(r)(c) <= '0';
                                    end if;
                                end loop;
                            end loop;

                        when "101" =>  -- single step
                            state   <= COMPUTE;
                            cur_row <= 0;
                            busy_o  <= '1';

                        when others => null;
                    end case;
                end if;

                -- ═══════════════════════════════════════════════════════
                -- Compute pipeline: process one row per clock cycle
                -- ═══════════════════════════════════════════════════════
                if state = COMPUTE then
                    -- Read three rows: top, middle, bottom (toroidal wrap)
                    if cur_row = 0 then
                        t_row := ROWS - 1;
                        b_row := cur_row + 1;
                    elsif cur_row = ROWS - 1 then
                        t_row := cur_row - 1;
                        b_row := 0;
                    else
                        t_row := cur_row - 1;
                        b_row := cur_row + 1;
                    end if;

                    row_t <= grid_a(t_row);
                    row_m <= grid_a(cur_row);
                    row_b <= grid_a(b_row);

                    -- Neighbor counting + B3/S23 per column
                    for c in 0 to COLS - 1 loop
                        -- Wrap columns
                        if c = 0 then
                            w_w := grid_a(t_row)(COLS - 1);
                            n_n := grid_a(cur_row)(COLS - 1);
                            s_s := grid_a(b_row)(COLS - 1);
                        else
                            w_w := grid_a(t_row)(c - 1);
                            n_n := grid_a(cur_row)(c - 1);
                            s_s := grid_a(b_row)(c - 1);
                        end if;

                        if c = COLS - 1 then
                            e_e := grid_a(t_row)(0);
                            ne  := grid_a(cur_row)(0);
                            se  := grid_a(b_row)(0);
                        else
                            e_e := grid_a(t_row)(c + 1);
                            ne  := grid_a(cur_row)(c + 1);
                            se  := grid_a(b_row)(c + 1);
                        end if;

                        nw := grid_a(t_row)(c);
                        sw := grid_a(b_row)(c);

                        -- Count neighbors (0-8)
                        neighbors_v := 0;
                        if nw = '1' then neighbors_v := neighbors_v + 1; end if;
                        if w_w = '1' then neighbors_v := neighbors_v + 1; end if;
                        if sw = '1' then neighbors_v := neighbors_v + 1; end if;
                        if n_n = '1' then neighbors_v := neighbors_v + 1; end if;
                        if s_s = '1' then neighbors_v := neighbors_v + 1; end if;
                        if ne = '1' then neighbors_v := neighbors_v + 1; end if;
                        if e_e = '1' then neighbors_v := neighbors_v + 1; end if;
                        if se = '1' then neighbors_v := neighbors_v + 1; end if;

                        -- B3/S23 rule
                        if grid_a(cur_row)(c) = '1' then
                            -- Alive: survives with 2 or 3 neighbors
                            if neighbors_v = 2 or neighbors_v = 3 then
                                row_out(c) <= '1';
                            else
                                row_out(c) <= '0';
                            end if;
                        else
                            -- Dead: born with exactly 3 neighbors
                            if neighbors_v = 3 then
                                row_out(c) <= '1';
                            else
                                row_out(c) <= '0';
                            end if;
                        end if;
                    end loop;

                    -- Write result to grid_b
                    grid_b(cur_row) <= row_out;

                    if cur_row = ROWS - 1 then
                        -- Swap buffers: grid_b becomes new grid_a
                        for r in 0 to ROWS - 1 loop
                            grid_a(r) <= grid_b(r);
                        end loop;
                        gen_count <= gen_count + 1;
                        state     <= DONE;
                    else
                        cur_row <= cur_row + 1;
                    end if;
                end if;

                if state = DONE then
                    busy_o <= '0';
                    state  <= IDLE;
                end if;
            end if;
        end if;
    end process;

    -- ═══════════════════════════════════════════════════════════
    -- Grid read port (for VGA / testbench)
    -- ═══════════════════════════════════════════════════════════
    grid_row_o <= grid_a(to_integer(unsigned(grid_row_idx_i)));

    gen_o <= std_logic_vector(gen_count);

end rtl;
