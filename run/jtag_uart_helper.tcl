# Read JTAG UART via nios2-terminal workaround
# Use Windows-native invocation to avoid MSYS terminal conflicts
proc read_jtag_uart {} {
    set timeout_ms 5000
    puts "Reading JTAG UART (timeout ${timeout_ms}ms)..."

    set pipe [open "|nios2-terminal.exe -q -o 5 2>@1" r]
    fconfigure $pipe -translation binary -buffering full

    set result ""
    set start [clock milliseconds]
    while {[clock milliseconds] - $start < $timeout_ms} {
        if {[catch {read $pipe 1} ch] || [eof $pipe]} break
        append result $ch
    }
    close $pipe
    return $result
}

puts [read_jtag_uart]
