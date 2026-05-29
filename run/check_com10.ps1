$sp = New-Object System.IO.Ports.SerialPort 'COM10',115200,'None',8,'one'
$sp.ReadTimeout = 300
$sp.WriteTimeout = 1000

try {
    $sp.Open()
    Start-Sleep -Milliseconds 200

    while ($sp.BytesToRead -gt 0) {
        [void]$sp.ReadExisting()
        Start-Sleep -Milliseconds 50
    }

    $sp.Write("`r")
    Start-Sleep -Milliseconds 500

    $out = ''
    $deadline = (Get-Date).AddSeconds(3)
    while ((Get-Date) -lt $deadline) {
        if ($sp.BytesToRead -gt 0) {
            $out += $sp.ReadExisting()
        }
        Start-Sleep -Milliseconds 100
    }

    if ([string]::IsNullOrEmpty($out)) {
        Write-Output '[no serial response]'
    } else {
        Write-Output $out
    }
} finally {
    if ($sp.IsOpen) {
        $sp.Close()
    }
}
