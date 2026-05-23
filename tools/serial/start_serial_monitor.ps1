param(
    [string]$Port = "COM10",
    [int]$BaudRate = 115200
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$logDir = Join-Path $root "logs"
$stateDir = Join-Path $root "run"
$logFile = Join-Path $logDir ("serial-{0}.log" -f $Port.ToLower())
$pidFile = Join-Path $stateDir ("serial-{0}.pid" -f $Port.ToLower())
$worker = Join-Path $PSScriptRoot "serial_monitor.ps1"

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

if (Test-Path $pidFile) {
    $existingPid = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($existingPid) {
        $proc = Get-Process -Id ([int]$existingPid) -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Output "already running pid=$existingPid log=$logFile"
            exit 0
        }
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

$argList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$worker`"",
    "-Port", "`"$Port`"",
    "-BaudRate", "$BaudRate",
    "-LogFile", "`"$logFile`"",
    "-PidFile", "`"$pidFile`""
)

$proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WindowStyle Hidden -PassThru
Start-Sleep -Milliseconds 500

$actualPid = $proc.Id
if (Test-Path $pidFile) {
    $actualPid = (Get-Content $pidFile | Select-Object -First 1).Trim()
}

Write-Output "started pid=$actualPid log=$logFile"
