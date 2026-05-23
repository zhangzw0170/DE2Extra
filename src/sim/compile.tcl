# QuestaSim compile & run script for Phase 2b testbenches
# Usage: questa> source sim/compile.tcl

# Compile design files
vcom -93 ../src/rtl/periph/font_rom_pkg.vhd
vcom -93 ../src/rtl/periph/vga_text_terminal.vhd
vcom -93 ../src/rtl/periph/ps2_sync.vhd
vcom -93 ../src/rtl/periph/ps2_receiver.vhd
vcom -93 ../src/rtl/periph/ps2_controller.vhd

# Compile testbenches
vcom -93 tb_vga_terminal.vhd

# Launch simulation (VGA terminal)
vsim tb_vga_terminal
add wave -divider "VGA Terminal"
add wave -radix hex sim:/tb_vga_terminal/u_dut/*
add wave -divider "Timing"
add wave sim:/tb_vga_terminal/vga_hs
add wave sim:/tb_vga_terminal/vga_vs
add wave sim:/tb_vga_terminal/vga_blank
run -all
