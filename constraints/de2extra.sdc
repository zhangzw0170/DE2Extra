# -------------------------------------------------------------------------- #
# DE2Extra — Timing Constraints                                              #
# -------------------------------------------------------------------------- #

# CPU clock: 50 MHz (20 ns period)
create_clock -name clk_50m -period 20.000 [get_ports {CLOCK_50}]

# False paths for asynchronous inputs
set_false_path -from [get_ports {KEY[*]}]

# SDRAM clock output (Phase 1 will add proper constraints)
set_output_delay -clock clk_50m -max 3.0 [get_ports {DRAM_CLK}]
set_output_delay -clock clk_50m -min -1.0 [get_ports {DRAM_CLK}]
