-- conway_engine.vhd — Conway's Game of Life hardware engine
--
-- 80x25 grid, B3/S23 rules, toroidal wrap, dual-buffered BRAM.
-- Wishbone slave for CPU control.
-- Hardware computes next generation; CPU reads grid for VGA display.
--
-- Slave registers (word-aligned, 4-byte stride):
--   0x00 [W] cmd: bit0=clear, bit1=randomize, bit2=step, bit3=auto_run
--   0x04 [W] control/data: bits[15:8]=row_index, bits[7:0]=seed(used by randomize)
--   0x08 [R] status: bit0=busy, bit1=auto_run, bits[17:2]=generation[15:0]
--   0x0C [R] population count [15:0]
--   0x10 [R] grid_row: returns 80-bit row data (read row_index set by last write to 0x04)
--              bits[79:0] = column alive/dead (1=alive), left-to-right

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity conway_engine is
    port (
        clk_i       : in  std_logic;
        rst_n_i     : in  std_logic;

        -- Wishbone slave (CPU registers)
        wb_adr_i    : in  std_logic_vector(4 downto 0);  -- word address [4:2]
        wb_dat_i    : in  std_logic_vector(31 downto 0);
        wb_dat_o    : out std_logic_vector(31 downto 0);
        wb_we_i     : in  std_logic;
        wb_stb_i    : in  std_logic;
        wb_ack_o    : out std_logic
    );
end entity conway_engine;

architecture rtl of conway_engine is

    constant COLS      : integer := 80;
    constant ROWS      : integer := 25;
    constant GRID_SIZE : integer := COLS * ROWS;  -- 2000

    -- Grid: 1 bit per cell, dual buffer
    type grid_t is array(0 to GRID_SIZE - 1) of std_logic;
    signal grid_a : grid_t := (others => '0');
    signal grid_b : grid_t := (others => '0');
    attribute ramstyle : string;
    attribute ramstyle of grid_a : signal is "M9K, no_rw_check";
    attribute ramstyle of grid_b : signal is "M9K, no_rw_check";

    -- Active buffer: '0' = A, '1' = B (flips after each generation)
    signal buf_sel    : std_logic := '0';
    signal auto_run   : std_logic := '0';

    -- Generation FSM (one cell per clock)
    type gen_state_t is (S_IDLE, S_COMPUTE, S_FLIP);
    signal gen_state  : gen_state_t := S_IDLE;
    signal gen_idx    : integer range 0 to GRID_SIZE - 1 := 0;
    signal gen_done_p : std_logic := '0';
    signal generation : unsigned(15 downto 0) := (others => '0');

    -- Population counter
    signal pop_count  : unsigned(15 downto 0) := (others => '0');
    signal pop_idx    : integer range 0 to GRID_SIZE - 1 := 0;
    signal pop_active : std_logic := '0';

    -- Row read register (set by write to 0x04, read at 0x10)
    signal row_idx    : integer range 0 to ROWS - 1 := 0;

    -- LFSR for random
    signal lfsr : unsigned(15 downto 0) := x"A59B";

begin

    -- ================================================================
    -- Wishbone Slave
    -- ================================================================
    process(clk_i)
        variable addr : integer range 0 to 7;
        variable row_idx_v : integer range 0 to ROWS - 1;
        variable rd_idx : integer;
        variable row_data : std_logic_vector(31 downto 0);
        variable rand_lfsr : unsigned(15 downto 0);
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                auto_run <= '0';
                generation <= (others => '0');
                grid_a <= (others => '0');
                grid_b <= (others => '0');
                buf_sel <= '0';
                row_idx <= 0;
            else
                wb_ack_o <= '0';
                wb_dat_o <= (others => '0');

                if wb_stb_i = '1' then
                    wb_ack_o <= '1';
                    addr := to_integer(unsigned(wb_adr_i(4 downto 2)));

                    if wb_we_i = '1' then
                        case addr is
                            when 0 =>  -- cmd
                                if wb_dat_i(0) = '1' then  -- clear
                                    auto_run <= '0';
                                    grid_a <= (others => '0');
                                    grid_b <= (others => '0');
                                    generation <= (others => '0');
                                    buf_sel <= '0';
                                end if;
                                if wb_dat_i(1) = '1' then  -- randomize
                                    rand_lfsr := unsigned(wb_dat_i(15 downto 0));
                                    for i in 0 to GRID_SIZE - 1 loop
                                        rand_lfsr := rand_lfsr(14 downto 0) &
                                                     (rand_lfsr(15) xor rand_lfsr(14) xor rand_lfsr(12) xor rand_lfsr(3));
                                        if rand_lfsr(3 downto 0) = "0000" then
                                            if buf_sel = '0' then grid_a(i) <= '1';
                                            else grid_b(i) <= '1'; end if;
                                        else
                                            if buf_sel = '0' then grid_a(i) <= '0';
                                            else grid_b(i) <= '0'; end if;
                                        end if;
                                    end loop;
                                    lfsr <= rand_lfsr;
                                end if;
                                if wb_dat_i(2) = '1' and gen_state = S_IDLE then  -- step
                                    gen_state <= S_COMPUTE;
                                    gen_idx <= 0;
                                end if;
                                if wb_dat_i(3) = '1' then  -- auto_run toggle
                                    auto_run <= not auto_run;
                                end if;
                            when 1 =>  -- control: set row_index for row read
                                row_idx_v := to_integer(unsigned(wb_dat_i(12 downto 8)));
                                if row_idx_v < ROWS then
                                    row_idx <= row_idx_v;
                                end if;
                            when others => null;
                        end case;
                    else
                        case addr is
                            when 2 =>  -- status
                                if gen_state /= S_IDLE then
                                    wb_dat_o(0) <= '1';
                                else
                                    wb_dat_o(0) <= '0';
                                end if;
                                wb_dat_o(1) <= auto_run;
                                wb_dat_o(17 downto 2) <= std_logic_vector(generation);
                            when 3 =>  -- population
                                wb_dat_o(15 downto 0) <= std_logic_vector(pop_count);
                            when 4 =>  -- grid_row
                                rd_idx := row_idx * COLS;
                                row_data := (others => '0');
                                for c in 0 to 31 loop
                                    if buf_sel = '0' then
                                        row_data(c) := grid_a(rd_idx);
                                    else
                                        row_data(c) := grid_b(rd_idx);
                                    end if;
                                    rd_idx := rd_idx + 1;
                                end loop;
                                wb_dat_o <= row_data;
                            when others => null;
                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ================================================================
    -- Next Generation: 1 cell per clock
    -- ================================================================
    process(clk_i)
        variable y, x, di : integer;
        variable ny, nx : integer;
        variable n_count : unsigned(3 downto 0);
        variable alive, next_alive : std_logic;
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                gen_state <= S_IDLE;
                gen_idx <= 0;
            else
                gen_done_p <= '0';

                if auto_run = '1' and gen_state = S_IDLE then
                    gen_state <= S_COMPUTE;
                    gen_idx <= 0;
                end if;

                case gen_state is
                    when S_IDLE => null;

                    when S_COMPUTE =>
                        y := gen_idx / COLS;
                        x := gen_idx mod COLS;
                        di := gen_idx;

                        if buf_sel = '0' then
                            alive := grid_a(di);
                        else
                            alive := grid_b(di);
                        end if;

                        n_count := (others => '0');
                        for dy in -1 to 1 loop
                            for dx in -1 to 1 loop
                                if dy /= 0 or dx /= 0 then
                                    ny := (y + dy + ROWS) mod ROWS;
                                    nx := (x + dx + COLS) mod COLS;
                                    di := ny * COLS + nx;
                                    if buf_sel = '0' then
                                        if grid_a(di) = '1' then n_count := n_count + 1; end if;
                                    else
                                        if grid_b(di) = '1' then n_count := n_count + 1; end if;
                                    end if;
                                end if;
                            end loop;
                        end loop;

                        if alive = '1' then
                            if (n_count = 2) or (n_count = 3) then
                                next_alive := '1';
                            else
                                next_alive := '0';
                            end if;
                        else
                            if n_count = 3 then
                                next_alive := '1';
                            else
                                next_alive := '0';
                            end if;
                        end if;

                        di := gen_idx;
                        if buf_sel = '0' then grid_b(di) <= next_alive;
                        else grid_a(di) <= next_alive; end if;

                        if gen_idx = GRID_SIZE - 1 then
                            gen_state <= S_FLIP;
                        else
                            gen_idx <= gen_idx + 1;
                        end if;

                    when S_FLIP =>
                        buf_sel <= not buf_sel;
                        generation <= generation + 1;
                        gen_done_p <= '1';
                        gen_state <= S_IDLE;
                        pop_idx <= 0;
                        pop_count <= (others => '0');
                        pop_active <= '1';

                end case;
            end if;
        end if;
    end process;

    -- ================================================================
    -- Population Counter
    -- ================================================================
    process(clk_i)
        variable di : integer;
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                pop_active <= '0';
                pop_count <= (others => '0');
            else
                if pop_active = '1' then
                    di := pop_idx;
                    if buf_sel = '0' then
                        if grid_a(di) = '1' then pop_count <= pop_count + 1; end if;
                    else
                        if grid_b(di) = '1' then pop_count <= pop_count + 1; end if;
                    end if;
                    if pop_idx = GRID_SIZE - 1 then
                        pop_active <= '0';
                    else
                        pop_idx <= pop_idx + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
