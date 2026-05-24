package require jtag_avalon_uart
set uart [jtag_avalon_uart::create]
$uart open -device 1 -instance 0
# Read available data
after 500
set data [$uart read 8192]
puts $data
$uart close
