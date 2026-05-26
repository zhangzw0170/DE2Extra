$targets = @(
    @{ Name = 'python.exe'; Match = 'upload_de2os.py' },
    @{ Name = 'python.exe'; Match = 'upload_de2os_jtag.tcl' },
    @{ Name = 'python.exe'; Match = 'capture_vga.py' },
    @{ Name = 'system-console.exe'; Match = 'upload_de2os_jtag.tcl' },
    @{ Name = 'nios2-terminal.exe'; Match = '' }
)

$killed = @()

foreach ($target in $targets) {
    $procs = Get-CimInstance Win32_Process -Filter "Name = '$($target.Name)'" -ErrorAction SilentlyContinue
    foreach ($proc in $procs) {
        $cmd = if ($null -ne $proc.CommandLine) { $proc.CommandLine } else { '' }
        if (($target.Match -eq '') -or ($cmd -like "*$($target.Match)*")) {
            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
                $killed += [pscustomobject]@{
                    Id   = $proc.ProcessId
                    Name = $proc.Name
                    Match = $target.Match
                }
            } catch {
            }
        }
    }
}

if ($killed.Count -eq 0) {
    Write-Host 'No stale upload/terminal processes found.'
} else {
    $killed | Sort-Object Name, Id | Format-Table -AutoSize
}
