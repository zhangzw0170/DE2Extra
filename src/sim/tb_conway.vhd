-- tb_conway.vhd — Conway Engine testbench: 验证滑翔机 4 代移动
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_conway is
end tb_conway;

architecture sim of tb_conway is
    signal clk      : std_logic := '0';
    signal rst_n    : std_logic := '0';
    signal cmd      : std_logic_vector(2 downto 0) := "000";
    signal cmd_val  : std_logic := '0';
    signal gen      : std_logic_vector(31 downto 0);
    signal busy     : std_logic;
    signal grid_row : std_logic_vector(79 downto 0);
    signal row_idx  : std_logic_vector(4 downto 0) := (others => '0');

    constant CLK_PERIOD : time := 20 ns;

    -- Expected glider positions after N generations
    -- Starting at (38,11): top at (38,11), left at (38,13), right at (39,12)
    procedure check_glider(
        gen_num  : in integer;
        expected_x : in integer;
        expected_y : in integer
    ) is
    begin
        -- After each generation, glider moves SE by 1 pixel
        -- origin cell moves from (38,11) + (gen, gen)
        report "Gen " & integer'image(gen_num) &
               ": expecting glider at (" & integer'image(expected_x) &
               "," & integer'image(expected_y) & ")";
    end procedure;

begin
    clk <= not clk after CLK_PERIOD / 2;

    u_dut : entity work.conway_engine
    port map (
        clk_i       => clk,
        rst_n_i     => rst_n,
        cmd_i       => cmd,
        cmd_valid_i => cmd_val,
        gen_o       => gen,
        busy_o      => busy,
        grid_row_o  => grid_row,
        grid_row_idx_i => row_idx,
        grid_page_i => '0'
    );

    process
        procedure do_cmd(c : std_logic_vector(2 downto 0)) is
        begin
            cmd <= c;
            cmd_val <= '1';
            wait until rising_edge(clk);
            cmd_val <= '0';
            wait until rising_edge(clk);
        end procedure;

        procedure do_step is
        begin
            do_cmd("101");
            -- Wait for computation to complete (25 + 2 clocks)
            wait until busy = '0';
            wait until rising_edge(clk);
        end procedure;

    begin
        report "=== Conway Engine Testbench ===";

        -- Reset
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait for 100 ns;

        -- Test 1: Load glider
        report "Test 1: Load glider pattern";
        do_cmd("010");  -- glider
        wait for 50 ns;

        -- Read row 11, should have cell at col 38
        row_idx <= std_logic_vector(to_unsigned(11, 5));
        wait for 100 ns;
        assert grid_row(38) = '1'
            report "ERROR: glider not placed at (38,11)" severity error;
        report "  Glider placed at (38,11): row[38]=" & std_logic'image(grid_row(38));

        -- Test 2: Step 1
        report "Test 2: Step 1 generation";
        do_step;
        check_glider(1, 39, 12);

        -- Test 3: Step 2
        report "Test 3: Step 2 generations";
        do_step;
        do_step;
        check_glider(3, 41, 14);

        -- Test 4: Verification — check cell (41,14) row 14 has alive cell
        row_idx <= std_logic_vector(to_unsigned(14, 5));
        wait for 100 ns;
        report "  Row 14 col 41 = " & std_logic'image(grid_row(41));

        report "=== All tests complete ===";
        wait;
    end process;
end sim;
