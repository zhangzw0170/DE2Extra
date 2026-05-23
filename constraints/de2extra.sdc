# -------------------------------------------------------------------------- #
# DE2Extra — Timing Constraints                                              #
# -------------------------------------------------------------------------- #

# CPU clock: 50 MHz (20 ns period)
create_clock -name clk_50m -period 20.000 [get_ports {CLOCK_50}]

# Let TimeQuest derive the PLL-generated internal clocks from CLOCK_50.
derive_pll_clocks
derive_clock_uncertainty

# SDRAM clock: 100 MHz (10 ns period) — PLL generated
create_clock -name clk_sdram -period 10.000 [get_ports {DRAM_CLK}]

# 50MHz CPU 与 100MHz SDRAM 是异步时钟域 (跨时钟域由同步器处理)
set_clock_groups -asynchronous \
    -group [get_clocks {clk_50m}] \
    -group [get_clocks {clk_sdram}]

# False paths for asynchronous inputs
set_false_path -from [get_ports {KEY[*]}]

# TRNG ring oscillators are intentionally unclocked (warnings are harmless)
set_false_path -to [get_registers {neorv32_wrapper:u_cpu|neorv32_top:u_neorv32|*neoTRNG*|*sreg*}]

# SDRAM address/command relative to SDRAM clock
set_output_delay -clock clk_sdram -max 2.0 [get_ports {DRAM_ADDR[*]}]
set_output_delay -clock clk_sdram -min 0.5 [get_ports {DRAM_ADDR[*]}]
set_output_delay -clock clk_sdram -max 2.0 [get_ports {DRAM_BA[*]}]
set_output_delay -clock clk_sdram -min 0.5 [get_ports {DRAM_BA[*]}]
set_output_delay -clock clk_sdram -max 2.0 [get_ports {DRAM_CAS_N DRAM_RAS_N DRAM_WE_N DRAM_CS_N}]
set_output_delay -clock clk_sdram -min 0.5 [get_ports {DRAM_CAS_N DRAM_RAS_N DRAM_WE_N DRAM_CS_N}]
set_output_delay -clock clk_sdram -max 2.0 [get_ports {DRAM_DQM[*]}]
set_output_delay -clock clk_sdram -min 0.5 [get_ports {DRAM_DQM[*]}]
