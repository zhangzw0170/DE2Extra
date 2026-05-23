param(
    [string]$Port = "COM10",
    [int]$BaudRate = 115200,
    [string]$LogFile = "",
    [string]$PidFile = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($LogFile)) {
    throw "LogFile is required."
}

$logDir = Split-Path -Parent $LogFile
if ($logDir) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

$pidDir = Split-Path -Parent $PidFile
if ($PidFile -and $pidDir) {
    New-Item -ItemType Directory -Force -Path $pidDir | Out-Null
}

$enc = [System.Text.Encoding]::ASCII

function Write-LogText {
    param([string]$Text)
    [System.IO.File]::AppendAllText($LogFile, $Text, $enc)
}

if ($PidFile) {
    Set-Content -Path $PidFile -Value $PID -Encoding ASCII
}

Write-LogText("`r`n===== serial monitor start $(Get-Date -Format s) port=$Port baud=$BaudRate =====`r`n")

$portObj = $null

try {
    while ($true) {
        try {
            if ($portObj -eq $null) {
                $portObj = New-Object System.IO.Ports.SerialPort $Port, $BaudRate, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
                $portObj.ReadTimeout = 200
                $portObj.WriteTimeout = 200
                $portObj.DtrEnable = $false
                $portObj.RtsEnable = $false
                $portObj.Handshake = [System.IO.Ports.Handshake]::None
                $portObj.Encoding = $enc
                $portObj.Open()
                Write-LogText("[$(Get-Date -Format s)] port opened`r`n")
            }

            if ($portObj.BytesToRead -gt 0) {
                $chunk = $portObj.ReadExisting()
                if ($chunk.Length -gt 0) {
                    Write-LogText($chunk)
                }
            } else {
                Start-Sleep -Milliseconds 50
            }
        }
        catch {
            Write-LogText("`r`n[$(Get-Date -Format s)] serial error: $($_.Exception.Message)`r`n")

            if ($portObj -ne $null) {
                try {
                    if ($portObj.IsOpen) {
                        $portObj.Close()
                    }
                }
                catch {
                }
                $portObj.Dispose()
                $portObj = $null
            }

            Start-Sleep -Seconds 1
        }
    }
}
finally {
    if ($portObj -ne $null) {
        try {
            if ($portObj.IsOpen) {
                $portObj.Close()
            }
        }
        catch {
        }
        $portObj.Dispose()
    }

    if ($PidFile -and (Test-Path $PidFile)) {
        Remove-Item -LiteralPath $PidFile -Force
    }

    Write-LogText("`r`n===== serial monitor stop $(Get-Date -Format s) =====`r`n")
}
