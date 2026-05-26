set BAUD_APP 115200
set PROMPT "CMD:> "

proc log {msg} {
    puts $msg
    flush stdout
}

proc to_u8_list {data} {
    set values {}
    binary scan $data c* raw
    foreach b $raw {
        lappend values [expr {($b + 256) & 0xff}]
    }
    return $values
}

proc bytes_to_string {values} {
    set raw {}
    foreach v $values {
        set b [expr {$v & 0xff}]
        if {$b > 127} {
            set b [expr {$b - 256}]
        }
        lappend raw $b
    }
    return [binary format c* {*}$raw]
}

proc send_ascii {path text} {
    bytestream_send $path [to_u8_list $text]
}

proc recv_until {path patterns timeout_ms} {
    set buf ""
    set deadline [expr {[clock milliseconds] + $timeout_ms}]

    while {[clock milliseconds] < $deadline} {
        set values [bytestream_receive $path 4096]
        if {[llength $values] > 0} {
            set chunk [bytes_to_string $values]
            append buf $chunk
            puts -nonewline $chunk
            flush stdout
            foreach p $patterns {
                if {[string first $p $buf] >= 0} {
                    return [list $buf $p]
                }
            }
        } else {
            after 20
        }
    }

    return [list $buf ""]
}

proc wait_for_prompt {path wait_mode} {
    if {$wait_mode} {
        log "Waiting for bootloader via JTAG UART..."
        log "Press KEY0 now."
        set initial_timeout 25000
    } else {
        log "Connecting to bootloader via JTAG UART..."
        set initial_timeout 12000
    }

    lassign [recv_until $path [list $::PROMPT "Auto-boot"] $initial_timeout] _buf matched
    if {$matched eq $::PROMPT} {
        return 1
    }

    send_ascii $path " "
    lassign [recv_until $path [list $::PROMPT] 3000] _buf2 matched2
    return [expr {$matched2 eq $::PROMPT}]
}

proc send_file {path binfile} {
    set fh [open $binfile rb]
    fconfigure $fh -translation binary -encoding binary
    set data [read $fh]
    close $fh

    set bytes [to_u8_list $data]
    set total [llength $bytes]
    set chunk_size 64

    log "Uploading $total bytes via JTAG-backed UART..."
    for {set i 0} {$i < $total} {incr i $chunk_size} {
        set chunk [lrange $bytes $i [expr {$i + $chunk_size - 1}]]
        bytestream_send $path $chunk
        after [expr {int(([llength $chunk] * 10.0 * 1000.0 / $::BAUD_APP) + 2.0)}]
    }

    return $total
}

if {$argc < 1} {
    error "usage: system-console --script upload_de2os_jtag.tcl <binfile> [--wait]"
}

set binfile [lindex $argv 0]
set wait_mode 0
if {$argc >= 2 && [lindex $argv 1] eq "--wait"} {
    set wait_mode 1
}

set paths [get_service_paths bytestream]
if {[llength $paths] == 0} {
    error "No JTAG bytestream service found."
}
set path [lindex $paths 0]

open_service bytestream $path
catch {bytestream_receive $path 8192}

if {![wait_for_prompt $path $wait_mode]} {
    close_service bytestream $path
    error "Bootloader prompt not detected on JTAG UART."
}

send_ascii $path "u"
lassign [recv_until $path [list "Awaiting"] 3000] _buf3 matched3
if {$matched3 ne "Awaiting"} {
    close_service bytestream $path
    error "Bootloader did not enter upload mode."
}

set total [send_file $path $binfile]
set upload_timeout [expr {int(($total * 10.0 * 1000.0 / $::BAUD_APP) + 4000.0)}]
lassign [recv_until $path [list "OK" "ERROR" $::PROMPT] $upload_timeout] resp matched4
if {[string first "OK" $resp] < 0} {
    close_service bytestream $path
    error "Upload failed: bootloader did not respond with OK."
}

log "Upload OK!"
send_ascii $path "e"
after 300
catch {recv_until $path {} 8000}
close_service bytestream $path
