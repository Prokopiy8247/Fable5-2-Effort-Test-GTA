<#
.SYNOPSIS
  Lead-side health watchdog while agent waves run. Read-only: it never kills or starts anything.
  Exits early (non-zero) when something needs the lead's attention, otherwise after -Minutes.
  Appends GPU samples to qa/logs/gpu_watch.csv (evidence for the GPU-safety section of the docs).
#>
param([int]$Minutes = 25, [int]$IntervalSec = 30)
$ErrorActionPreference = 'Continue'
$Proj = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$csv = Join-Path $Proj 'qa\logs\gpu_watch.csv'
New-Item -ItemType Directory -Force (Split-Path $csv) | Out-Null
if (-not (Test-Path $csv)) { 'time,gpu_util,vram_used_mb,vram_total_mb,temp_c,blender_port,godot_ours' | Out-File -Encoding ascii $csv }

function Test-Port([int]$Port) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(1500) -and $c.Connected
        $c.Close(); return $ok
    } catch { return $false }
}

$deadline = (Get-Date).AddMinutes($Minutes)
$portDown = 0; $gpuHot = 0; $maxUtil = 0; $maxMem = 0; $samples = 0
while ((Get-Date) -lt $deadline) {
    $line = (& nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
    $util = 0; $mem = 0; $tot = 1; $temp = 0
    if ($line) { $p = $line -split ','; $util = [int]$p[0].Trim(); $mem = [int]$p[1].Trim(); $tot = [int]$p[2].Trim(); $temp = [int]$p[3].Trim() }
    $port = Test-Port 9882
    $ours = @(Get-CimInstance Win32_Process -Filter "Name like 'Godot%'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($Proj) })
    $old = @($ours | Where-Object { ((Get-Date) - $_.CreationDate).TotalMinutes -gt 9 })
    ('{0},{1},{2},{3},{4},{5},{6}' -f (Get-Date -Format o), $util, $mem, $tot, $temp, [int]$port, $ours.Count) | Add-Content -Path $csv
    $samples++; if ($util -gt $maxUtil) { $maxUtil = $util }; if ($mem -gt $maxMem) { $maxMem = $mem }
    if ($port) { $portDown = 0 } else { $portDown++ }
    if ($util -ge 97 -and (100.0 * $mem / $tot) -ge 92) { $gpuHot++ } else { $gpuHot = 0 }
    if ($portDown -ge 8) { Write-Output "WATCHDOG ALERT: Blender MCP port 9882 closed for $($portDown * $IntervalSec) s"; exit 2 }
    if ($old.Count -gt 0) { Write-Output "WATCHDOG ALERT: a Godot process of this project has been running for more than 9 minutes (pid $($old.ProcessId -join ','))"; exit 3 }
    if ($gpuHot -ge 6) { Write-Output "WATCHDOG ALERT: GPU saturated (util >= 97 % and VRAM >= 92 %) for $($gpuHot * $IntervalSec) s"; exit 4 }
    Start-Sleep -Seconds $IntervalSec
}
Write-Output ("WATCHDOG OK: {0} samples over {1} min, max GPU util {2} %, max VRAM {3} MiB, Blender port up" -f $samples, $Minutes, $maxUtil, $maxMem)
exit 0
