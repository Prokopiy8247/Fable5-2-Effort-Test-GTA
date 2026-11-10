# Safe Godot launcher for automated runs (see spec section 3A).
#  - exactly one Godot instance from this project at a time (pid file)
#  - every run has a hard frame limit AND an OS-level timeout, then the process tree is killed
#  - windowed (GPU) runs wait while the shared GPU is busy (>85% util or VRAM)
#  - windowed runs are capped to 60 fps at 1280x720 by default
param(
    [ValidateSet('headless', 'window', 'import', 'script', 'editorcheck')]
    [string]$Mode = 'headless',
    [int]$Frames = 600,
    [int]$TimeoutSec = 120,
    [string]$Name = 'run',
    [string]$Script = '',
    [string]$Resolution = '1280x720',
    [string[]]$UserArgs = @(),
    [switch]$NoImport
)

$ErrorActionPreference = 'Stop'
$proj = Split-Path -Parent $PSScriptRoot
$godot = 'W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'
$logDir = Join-Path $proj 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$pidFile = Join-Path $logDir 'godot.pid'
$logFile = Join-Path $logDir ($Name + '.log')

# --- single instance guard -------------------------------------------------
if (Test-Path $pidFile) {
    $old = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($old) {
        $op = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
        if ($op -and $op.ProcessName -like 'Godot*') {
            Write-Output "GUARD: previous Godot instance (pid $old) still alive - killing it first"
            & taskkill /F /T /PID $old 2>$null | Out-Null
            Start-Sleep -Seconds 1
        }
    }
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}

# --- GPU back-off for rendering runs ----------------------------------------
if ($Mode -eq 'window') {
    $tries = 0
    while ($tries -lt 16) {
        $q = & nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null
        if (-not $q) { break }
        $parts = ($q | Select-Object -First 1) -split ','
        $util = [int]$parts[0].Trim(); $used = [double]$parts[1].Trim(); $total = [double]$parts[2].Trim()
        $memPct = [math]::Round(100.0 * $used / $total)
        if ($util -le 85 -and $memPct -le 85) {
            Write-Output "GPU ok: util=$util% vram=$memPct%"
            break
        }
        Write-Output "GPU busy (util=$util% vram=$memPct%) - waiting 15s"
        Start-Sleep -Seconds 15
        $tries++
    }
    if ($tries -ge 16) {
        Write-Output 'GPU still busy after 4 minutes - aborting this rendering run'
        exit 3
    }
}

# --- automatic import / class-cache refresh when project files changed ---------
if (($Mode -eq 'headless' -or $Mode -eq 'window') -and -not $NoImport) {
    $stamp = Join-Path $logDir 'import.stamp'
    $newest = Get-ChildItem (Join-Path $proj 'gta') -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.gd', '.glb', '.wav', '.gdshader', '.tscn', '.tres', '.png', '.json' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $need = $true
    if ((Test-Path $stamp) -and $newest) {
        if ((Get-Item $stamp).LastWriteTime -ge $newest.LastWriteTime) { $need = $false }
    }
    if ($need) {
        $ilog = Join-Path $logDir 'import_auto.log'
        if (Test-Path $ilog) { Remove-Item $ilog -ErrorAction SilentlyContinue }
        $ia = @('--path', "`"$proj`"", '--log-file', "`"$ilog`"", '--headless', '--import')
        $isw = [System.Diagnostics.Stopwatch]::StartNew()
        $ip = Start-Process -FilePath $godot -ArgumentList $ia -PassThru -WindowStyle Hidden
        Set-Content -Path $pidFile -Value $ip.Id
        if (-not $ip.WaitForExit(300000)) {
            Write-Output 'IMPORT TIMEOUT - killing'
            & taskkill /F /T /PID $ip.Id 2>$null | Out-Null
        } else {
            Set-Content -Path $stamp -Value (Get-Date).ToString('o')
        }
        Remove-Item $pidFile -ErrorAction SilentlyContinue
        $ierr = @()
        if (Test-Path $ilog) { $ierr = Select-String -Path $ilog -Pattern 'ERROR|SCRIPT ERROR|Parse Error' -SimpleMatch:$false | Select-Object -First 12 }
        Write-Output ("IMPORT pass: {0:n1}s, {1} error line(s)" -f $isw.Elapsed.TotalSeconds, $ierr.Count)
        foreach ($e in $ierr) { Write-Output ("  " + $e.Line) }
    }
}

# --- build argument list ----------------------------------------------------
$a = @('--path', "`"$proj`"", '--log-file', "`"$logFile`"")
switch ($Mode) {
    'headless'    { $a += @('--headless', '--fixed-fps', '60', '--quit-after', "$Frames") }
    'window'      { $a += @('--resolution', $Resolution, '--position', '40,40', '--max-fps', '60', '--quit-after', "$Frames") }
    'import'      { $a += @('--headless', '--import') }
    'script'      { $a += @('--headless', '--script', $Script) }
    'editorcheck' { $a += @('--headless', '--editor', '--quit') }
}
if ($UserArgs.Count -gt 0) { $a += '--'; $a += $UserArgs }

if (Test-Path $logFile) { Remove-Item $logFile -ErrorAction SilentlyContinue }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $godot -ArgumentList $a -PassThru -WindowStyle Normal
Set-Content -Path $pidFile -Value $p.Id
$finished = $p.WaitForExit($TimeoutSec * 1000)
if (-not $finished) {
    Write-Output "TIMEOUT after $TimeoutSec s - killing Godot (pid $($p.Id))"
    & taskkill /F /T /PID $p.Id 2>$null | Out-Null
    Start-Sleep -Milliseconds 500
}
$sw.Stop()
Remove-Item $pidFile -ErrorAction SilentlyContinue
$code = 'killed'
if ($finished) { $code = $p.ExitCode }
Write-Output ("GODOT {0} finished: exit={1} time={2:n1}s log={3}" -f $Mode, $code, $sw.Elapsed.TotalSeconds, $logFile)
if ($finished) { exit $p.ExitCode } else { exit 124 }
