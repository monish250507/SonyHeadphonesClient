<#
.SYNOPSIS
    Smart persistent background supervisor for Sony Headphones Client.
    Supports Sony WH-CH520 and modern headsets (V2 Protocol) as well as legacy headsets (V1).
#>
param(
    [ValidateSet("Auto", "V2", "V1")]
    [string]$Engine = "Auto",
    [string]$Model = "WH-CH520",
    [switch]$Daemon,
    [switch]$Stop,
    [switch]$Status
)

$releaseDir = Join-Path $PSScriptRoot "release"
$exeV1 = Join-Path $releaseDir "SonyHeadphonesClient.exe"
$exeV2 = Join-Path $releaseDir "SonyHeadphonesClient-v2.exe"

# Resolve which engine binary to run
function Get-TargetExecutable {
    param([string]$PreferredEngine, [string]$TargetModel)

    if ($PreferredEngine -eq "V1") {
        if (Test-Path $exeV1) { return $exeV1 }
    }
    if ($PreferredEngine -eq "V2") {
        if (Test-Path $exeV2) { return $exeV2 }
    }

    # Auto detection: Check paired Bluetooth devices
    try {
        $pnpDevices = Get-PnpDevice -Class "Bluetooth" -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName }
        $devNames = $pnpDevices.FriendlyName -join " "

        # Known modern Protocol V2 models
        $v2Pattern = "WH-CH520|WH-CH720N|WH-1000XM4|WH-1000XM5|WF-1000XM4|WF-1000XM5|WF-C500|WF-C510|WF-C700N|LinkBuds"
        
        if ($TargetModel -match $v2Pattern -or $devNames -match $v2Pattern) {
            if (Test-Path $exeV2) { return $exeV2 }
        }
    } catch {}

    # Default to V2 if WH-CH520 or modern headsets, fallback to V1
    if (Test-Path $exeV2) { return $exeV2 }
    return $exeV1
}

$chosenExe = Get-TargetExecutable -PreferredEngine $Engine -TargetModel $Model

# Stop action: Terminates both supervisor daemon and any active clients
if ($Stop) {
    Write-Host "Stopping Sony Headphones Client and supervisor..." -ForegroundColor Yellow
    Get-CimInstance Win32_Process | Where-Object { 
        $_.CommandLine -like "*Start-SonyClient.ps1*Daemon*" -and $_.ProcessId -ne $PID 
    } | ForEach-Object { 
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue 
    }
    
    Get-Process -Name "*SonyHeadphonesClient*" -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Sony Headphones Client and supervisor stopped." -ForegroundColor Green
    exit 0
}

# Status action: Checks running status of client and supervisor
if ($Status) {
    $proc = Get-Process | Where-Object { $_.ProcessName -like "*SonyHeadphonesClient*" } | Select-Object -First 1
    $supervisor = Get-CimInstance Win32_Process | Where-Object { 
        $_.CommandLine -like "*Start-SonyClient.ps1*Daemon*" -and $_.ProcessId -ne $PID 
    }

    if ($proc) {
        $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
        $engineType = if ($proc.ProcessName -like "*-v2*") { "Protocol V2 (WH-CH520 Compatible)" } else { "Protocol V1 (Legacy)" }
        Write-Host "Client Status     : ACTIVE (PID: $($proc.Id), Engine: $engineType, Memory: $memMB MB)" -ForegroundColor Green
    } else {
        Write-Host "Client Status     : STOPPED" -ForegroundColor Red
    }

    if ($supervisor) {
        Write-Host "Supervisor Daemon : ACTIVE (PID: $($supervisor.ProcessId))" -ForegroundColor Green
    } else {
        Write-Host "Supervisor Daemon : INACTIVE" -ForegroundColor Yellow
    }
    exit 0
}

# If not running in Daemon mode, start the daemon detached in background
if (-not $Daemon) {
    $supervisor = Get-CimInstance Win32_Process | Where-Object { 
        $_.CommandLine -like "*Start-SonyClient.ps1*Daemon*" -and $_.ProcessId -ne $PID 
    }
    $client = Get-Process | Where-Object { $_.ProcessName -like "*SonyHeadphonesClient*" } | Select-Object -First 1

    if ($supervisor -and $client) {
        Write-Host "Sony Headphones Client is already actively running (PID: $($client.Id))." -ForegroundColor Cyan
        exit 0
    }

    Write-Host "Starting Sony Headphones Client supervisor for $Model..." -ForegroundColor Cyan
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Engine `"$Engine`" -Model `"$Model`" -Daemon"
    $psi.WorkingDirectory = $releaseDir
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    [System.Diagnostics.Process]::Start($psi) | Out-Null

    Start-Sleep -Seconds 2
    $client = Get-Process | Where-Object { $_.ProcessName -like "*SonyHeadphonesClient*" } | Select-Object -First 1
    if ($client) {
        Write-Host "Success! Client is active (PID: $($client.Id))." -ForegroundColor Green
    } else {
        Write-Host "Supervisor started. The client will run in the background." -ForegroundColor Green
    }
    exit 0
}

# DAEMON WATCHDOG: Keeps the target engine running continuously
while ($true) {
    try {
        $proc = Get-Process | Where-Object { $_.ProcessName -like "*SonyHeadphonesClient*" }
        if (-not $proc) {
            $p = New-Object System.Diagnostics.Process
            $p.StartInfo.FileName = $chosenExe
            $p.StartInfo.WorkingDirectory = $releaseDir
            $p.StartInfo.UseShellExecute = $true
            $p.Start() | Out-Null
            Start-Sleep -Seconds 3
        }
    } catch {
        # Keep watchdog alive
    }
    Start-Sleep -Seconds 2
}
