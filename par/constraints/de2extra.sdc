# -------------------------------------------------------------------------- #
# DE2Extra — Timing Constraints                                              #
# -------------------------------------------------------------------------- #

# CPU clock: 50 MHz (20 ns period)
create_clock -name clk_50m -period 20.000 [get_ports {CLOCK_50}]

# Let TimeQuest derive the PLL-generated internal clocks from CLOCK_50.
derive_pll_clocks
derive_clock_uncertainty

# VGA 25MHz pixel clock (derived from 50MHz toggle in vga_text_terminal).
# Quartus needs this to infer M9K dual-port BRAM instead of logic.
# NOTE: pin path is a placeholder — verify after first compile in Technology Map Viewer.
# Temporarily commented out until exact path is confirmed from first compilation.
# create_generated_clock -name clk_25m -period 40.000 \
#     -source [get_pins {de2_115_top|vga_text_terminal:u_vga|clk_25m~reg0}] \
#     [get_pins {de2_115_top|vga_text_terminal:u_vga|clk_25m~reg0}]

# SDRAM clock: 100 MHz (10 ns period) — PLL generated
create_clock -name clk_sdram -period 10.000 [get_ports {DRAM_CLK}]

# 50MHz CPU 与 100MHz SDRAM 是异步时钟域 (跨时钟域由同步器处理)
set_clock_groups -asynchronous \
    -group [get_clocks {clk_50m}] \
    -group [get_clocks {clk_sdram}]

# False paths for asynchronous inputs
set_false_path -from [get_ports {KEY[*]}]
set_false_path -from [get_ports {SW[*] UART_RXD PS2_CLK PS2_DAT IRDA_RXD altera_reserved_tdi altera_reserved_tms}]

# False paths for debug / human-interface outputs that have no FPGA-captured destination clock
set_false_path -to [get_ports {LEDR[*] LEDG[*]}]
set_false_path -to [get_ports {HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*] HEX6[*] HEX7[*]}]
set_false_path -to [get_ports {LCD_DATA[*] LCD_RS LCD_RW LCD_EN LCD_ON LCD_BLON}]
set_false_path -to [get_ports {UART_TXD PS2_CLK PS2_DAT altera_reserved_tdo}]
set_false_path -to [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS VGA_CLK VGA_SYNC_N VGA_BLANK_N}]

# SDRAM address/command relative to SDRAM clock
set_output_delay -clock clk_sdram -max 2.0 [get_ports {DRAM_ADDR[*]}]
set_output_delay -clock clk_sdram -min 0.5 [get_ports {DRAM_ADDR[*]}]
set_output_delay -clock clk_sdram -max 2.0 [get_ports {DRAM_BA[*]}]
set_output_delay -clock clk_sdram -min 0.5 [get_ports {DRAM_BA[*]}]
set_output_delay -clock clk_sdram -max 2.0 [get_ports {DRAM_CAS_N DRAM_RAS_N DRAM_WE_N DRAM_CS_N DRAM_cke}]
set_output_delay -clock clk_sdram -min 0.5 [get_ports {DRAM_CAS_N DRAM_RAS_N DRAM_WE_N DRAM_CS_N DRAM_cke}]
set_output_delay -clock clk_sdram -max 2.0 [get_ports {DRAM_DQM[*] DRAM_DQ[*]}]
set_output_delay -clock clk_sdram -min 0.5 [get_ports {DRAM_DQM[*] DRAM_DQ[*]}]

# SDRAM read data returns relative to the controller clock domain.
# These conservative numbers are sufficient to make the interface timed instead of unconstrained.
set_input_delay -clock clk_sdram -max 5.5 [get_ports {DRAM_DQ[*]}]
set_input_delay -clock clk_sdram -min 0.8 [get_ports {DRAM_DQ[*]}]
