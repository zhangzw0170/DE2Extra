param(
    [string]$Port = "COM10"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pidFile = Join-Path (Join-Path $root "run") ("serial-{0}.pid" -f $Port.ToLower())

if (-not (Test-Path $pidFile)) {
    Write-Output "not running"
    exit 0
}

$pidText = (Get-Content $pidFile | Select-Object -First 1).Trim()
if (-not $pidText) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-Output "stale pid file removed"
    exit 0
}

$proc = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
if ($proc) {
    Stop-Process -Id $proc.Id -Force
    Write-Output "stopped pid=$($proc.Id)"
} else {
    Write-Output "stale pid file removed"
}

Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
