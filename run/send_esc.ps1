param([string]$Port = "COM10", [int]$Baud = 115200)
$sp = New-Object System.IO.Ports.SerialPort $Port,$Baud,'None',8,'one'
$sp.ReadTimeout = 300
$sp.Open()
Start-Sleep -Milliseconds 200
while ($sp.BytesToRead -gt 0) {
    [void]$sp.ReadExisting()
    Start-Sleep -Milliseconds 50
}
$sp.Write([char]27)
Start-Sleep -Milliseconds 500
$out = ''
$dl = (Get-Date).AddSeconds(2)
while ((Get-Date) -lt $dl) {
    if ($sp.BytesToRead -gt 0) {
        $out += $sp.ReadExisting()
    }
    Start-Sleep -Milliseconds 100
}
$sp.Close()
if ([string]::IsNullOrEmpty($out)) {
    Write-Output '[no serial response]'
} else {
    Write-Output $out
}
