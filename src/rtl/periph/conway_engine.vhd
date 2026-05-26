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

    -- FSM state
    type fsm_mode_t is (FSM_IDLE, FSM_RAND, FSM_COMPUTE, FSM_FLIP, FSM_POP);
    signal fsm_mode   : fsm_mode_t := FSM_IDLE;
    signal fsm_idx    : integer range 0 to GRID_SIZE - 1 := 0;
    signal generation : unsigned(15 downto 0) := (others => '0');

    -- Population counter
    signal pop_count  : unsigned(15 downto 0) := (others => '0');
    signal pop_idx    : integer range 0 to GRID_SIZE - 1 := 0;

    -- Row read register (set by write to 0x04, read at 0x10)
    signal row_idx    : integer range 0 to ROWS - 1 := 0;

    -- LFSR
    signal lfsr : unsigned(15 downto 0) := x"A59B";
    signal rand_seed : unsigned(15 downto 0) := x"A59B";

    -- Busy (registered, set inside process for WB read consistency)
    signal busy : std_logic;

begin

    -- ================================================================
    -- Single unified process: WB slave + FSM
    -- Variables ensure request signals are visible within the same
    -- clock edge, avoiding the two-process race condition.
    -- ================================================================
    process(clk_i)
        variable addr : integer range 0 to 7;
        variable row_idx_v : integer range 0 to ROWS - 1;
        variable rd_idx : integer;
        variable row_data : std_logic_vector(31 downto 0);
        variable v_clear_req : std_logic;
        variable v_rand_req  : std_logic;
        variable v_step_req  : std_logic;
        variable v_rand_seed : unsigned(15 downto 0);
        variable auto_run   : std_logic := '0';
        variable y, x, di : integer;
        variable ny, nx : integer;
        variable n_count : unsigned(3 downto 0);
        variable alive, next_alive : std_logic;
        variable new_lfsr : unsigned(15 downto 0);
    begin
        if rising_edge(clk_i) then
            if rst_n_i = '0' then
                fsm_mode <= FSM_IDLE;
                fsm_idx <= 0;
                generation <= (others => '0');
                pop_count <= (others => '0');
                pop_idx <= 0;
                grid_a <= (others => '0');
                grid_b <= (others => '0');
                buf_sel <= '0';
                auto_run := '0';
                lfsr <= x"A59B";
                rand_seed <= x"A59B";
                row_idx <= 0;
                wb_dat_o <= (others => '0');
                wb_ack_o <= '0';
            else
                -- Defaults
                wb_ack_o <= '0';
                wb_dat_o <= (others => '0');

                -- WB request capture (variables — immediate effect)
                v_clear_req := '0';
                v_rand_req  := '0';
                v_step_req  := '0';
                v_rand_seed := rand_seed;

                -- Wishbone slave handling (process every clock stb is asserted)
                if wb_stb_i = '1' then
                    wb_ack_o <= '1';
                    addr := to_integer(unsigned(wb_adr_i(4 downto 2)));

                    if wb_we_i = '1' then
                        case addr is
                            when 0 =>  -- cmd
                                if wb_dat_i(0) = '1' then
                                    v_clear_req := '1';
                                end if;
                                if wb_dat_i(1) = '1' then
                                    v_rand_req := '1';
                                    v_rand_seed := unsigned(wb_dat_i(15 downto 0));
                                end if;
                                if wb_dat_i(2) = '1' then
                                    v_step_req := '1';
                                end if;
                                if wb_dat_i(3) = '1' then
                                    auto_run := not auto_run;
                                end if;
                            when 1 =>  -- control: set row_index
                                row_idx_v := to_integer(unsigned(wb_dat_i(12 downto 8)));
                                if row_idx_v < ROWS then
                                    row_idx <= row_idx_v;
                                end if;
                            when others => null;
                        end case;
                    else
                        case addr is
                            when 2 =>  -- status
                                wb_dat_o(0) <= busy;
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

                -- Store seed if requested
                if v_rand_req = '1' then
                    rand_seed <= v_rand_seed;
                end if;

                -- FSM
                case fsm_mode is
                    when FSM_IDLE =>
                        busy <= '0';
                        if v_clear_req = '1' then
                            auto_run := '0';
                            generation <= (others => '0');
                            pop_count <= (others => '0');
                            buf_sel <= '0';
                            grid_a <= (others => '0');
                            grid_b <= (others => '0');
                        elsif v_rand_req = '1' then
                            busy <= '1';
                            fsm_idx <= 0;
                            lfsr <= v_rand_seed;
                            fsm_mode <= FSM_RAND;
                        elsif (v_step_req = '1' or auto_run = '1') then
                            busy <= '1';
                            fsm_idx <= 0;
                            fsm_mode <= FSM_COMPUTE;
                        end if;

                    when FSM_RAND =>
                        new_lfsr := lfsr(14 downto 0) &
                                   (lfsr(15) xor lfsr(14) xor lfsr(12) xor lfsr(3));
                        if new_lfsr(3 downto 0) = "0000" then
                            if buf_sel = '0' then grid_a(fsm_idx) <= '1';
                            else grid_b(fsm_idx) <= '1'; end if;
                        else
                            if buf_sel = '0' then grid_a(fsm_idx) <= '0';
                            else grid_b(fsm_idx) <= '0'; end if;
                        end if;
                        lfsr <= new_lfsr;

                        if fsm_idx = GRID_SIZE - 1 then
                            fsm_mode <= FSM_IDLE;
                        else
                            fsm_idx <= fsm_idx + 1;
                        end if;

                    when FSM_COMPUTE =>
                        y := fsm_idx / COLS;
                        x := fsm_idx mod COLS;
                        di := fsm_idx;

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
                            if (n_count = 2) or (n_count = 3) then next_alive := '1';
                            else next_alive := '0'; end if;
                        else
                            if n_count = 3 then next_alive := '1';
                            else next_alive := '0'; end if;
                        end if;

                        di := fsm_idx;
                        if buf_sel = '0' then grid_b(di) <= next_alive;
                        else grid_a(di) <= next_alive; end if;

                        if fsm_idx = GRID_SIZE - 1 then
                            fsm_mode <= FSM_FLIP;
                        else
                            fsm_idx <= fsm_idx + 1;
                        end if;

                    when FSM_FLIP =>
                        buf_sel <= not buf_sel;
                        generation <= generation + 1;
                        pop_count <= (others => '0');
                        pop_idx <= 0;
                        fsm_mode <= FSM_POP;

                    when FSM_POP =>
                        di := pop_idx;
                        if buf_sel = '0' then
                            if grid_a(di) = '1' then pop_count <= pop_count + 1; end if;
                        else
                            if grid_b(di) = '1' then pop_count <= pop_count + 1; end if;
                        end if;

                        if pop_idx = GRID_SIZE - 1 then
                            fsm_mode <= FSM_IDLE;
                        else
                            pop_idx <= pop_idx + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
