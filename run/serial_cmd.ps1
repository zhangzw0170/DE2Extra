param(
    [string]$Port = "COM10",
    [int]$Baud = 115200,
    [string]$Command = "",
    [int]$ReadSeconds = 3
)

$sp = New-Object System.IO.Ports.SerialPort $Port,$Baud,'None',8,'one'
$sp.ReadTimeout = 300
$sp.WriteTimeout = 1000
$sp.NewLine = "`r"

try {
    $sp.Open()
    Start-Sleep -Milliseconds 200

    while ($sp.BytesToRead -gt 0) {
        [void]$sp.ReadExisting()
        Start-Sleep -Milliseconds 50
    }

    if ($Command -ne "") {
        $sp.Write($Command + "`r")
    } else {
        $sp.Write("`r")
    }

    Start-Sleep -Milliseconds 300

    $out = ''
    $deadline = (Get-Date).AddSeconds($ReadSeconds)
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
