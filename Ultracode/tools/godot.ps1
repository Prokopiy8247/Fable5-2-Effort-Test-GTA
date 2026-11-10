<#
.SYNOPSIS
  The ONLY permitted way to launch Godot for this project (see docs/ARCHITECTURE.md, "Godot run protocol").

  Guarantees required by the benchmark spec, section 3A:
    * at most ONE Godot instance of this project at a time (system-wide named mutex),
    * every run has a hard time limit (--quit-after + OS-level kill),
    * frame rate is always capped, resolution is modest,
    * windowed (GPU) runs wait while the shared GPU is above 85 % load / VRAM.

.EXAMPLE
  tools\godot.ps1 -Mode import
  tools\godot.ps1 -Mode check                      # parse-check every script under res://gta
  tools\godot.ps1 -Mode check -Dirs gta/code/player,gta/code/core
  tools\godot.ps1 -Mode headless -Frames 600 -UserArgs '--test=player_move'
  tools\godot.ps1 -Mode headless -Scene res://gta/tests/scenes/car_test.tscn -Frames 400
  tools\godot.ps1 -Mode window -Frames 300 -UserArgs '--test=shot_downtown'
  tools\godot.ps1 -Mode script -Script res://gta/code/editor/some_tool.gd
#>
param(
    [ValidateSet('import', 'check', 'headless', 'window', 'script', 'export')]
    [string]$Mode = 'headless',
    [string]$Scene = '',
    [string]$Script = '',
    [string]$Dirs = 'gta',
    [int]$Frames = 600,
    [int]$TimeoutSec = 150,
    [int]$Fps = 30,
    [string]$Res = '1280x720',
    [string[]]$UserArgs = @(),
    [string]$Tag = '',
    [switch]$NoImport,
    [int]$Tail = 40
)

$ErrorActionPreference = 'Continue'
$Godot = 'W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$Proj = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LogDir = Join-Path $Proj 'qa\logs'
New-Item -ItemType Directory -Force $LogDir | Out-Null
if ($Tag -eq '') { $Tag = $Mode }
$stamp = (Get-Date).ToString('HHmmss_fff')
$safeTag = ($Tag -replace '[^A-Za-z0-9_\-]', '_')
$LogOut = Join-Path $LogDir "$stamp`_$safeTag.out.log"
$LogErr = Join-Path $LogDir "$stamp`_$safeTag.err.log"

if ($TimeoutSec -gt 420) { $TimeoutSec = 420 }
if ($Fps -gt 60) { $Fps = 60 }
if ($Frames -lt 1) { $Frames = 1 }

function Quote-Arg([string]$a) {
    if ($a -match '[\s"]') { return '"' + ($a -replace '"', '\"') + '"' }
    return $a
}

function Stop-StrayGodot {
    # Only Godot processes that were started for THIS project path are ours to kill.
    try {
        Get-CimInstance Win32_Process -Filter "Name like 'Godot%'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine.Contains($Proj) } |
            ForEach-Object {
                Write-Host "[godot.ps1] killing stray Godot pid $($_.ProcessId) of this project"
                & taskkill /PID $_.ProcessId /T /F 2>$null | Out-Null
            }
    } catch {}
}

function Wait-Gpu {
    # Shared single GPU (other benchmark sessions run their own Godot/Blender on it).
    # Never add a windowed run on top of a busy GPU: sample 3x over ~2 s and use the PEAK.
    # Utilisation gate 65 % (stricter than the spec's 85 %, because our run itself adds ~30-40 %
    # and the combined load must stay clear of 100 %); VRAM gate 85 %.
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $smi) { return $true }
    for ($i = 0; $i -lt 16; $i++) {
        $util = 0; $mem = 0.0
        for ($s = 0; $s -lt 3; $s++) {
            $line = (& nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
            if (-not $line) { return $true }
            $p = $line -split ','
            $u = [int]$p[0].Trim(); $m = 100.0 * [double]$p[1].Trim() / [double]$p[2].Trim()
            if ($u -gt $util) { $util = $u }
            if ($m -gt $mem) { $mem = $m }
            if ($s -lt 2) { Start-Sleep -Milliseconds 900 }
        }
        if ($util -le 65 -and $mem -le 85) {
            Write-Host ("[godot.ps1] GPU ok: util {0}% vram {1:N0}%" -f $util, $mem)
            return $true
        }
        Write-Host ("[godot.ps1] GPU busy (util {0}% vram {1:N0}%), waiting 20 s ..." -f $util, $mem)
        Start-Sleep -Seconds 20
    }
    return $false
}

function Invoke-Godot([string[]]$GodotArgs, [int]$Timeout, [string]$Out, [string]$Err) {
    $argLine = ($GodotArgs | ForEach-Object { Quote-Arg $_ }) -join ' '
    $p = Start-Process -FilePath $Godot -ArgumentList $argLine -NoNewWindow -PassThru `
        -RedirectStandardOutput $Out -RedirectStandardError $Err -WorkingDirectory $Proj
    $null = $p.Handle   # cache the handle, otherwise ExitCode stays empty
    $finished = $p.WaitForExit($Timeout * 1000)
    if (-not $finished) {
        Write-Host "[godot.ps1] HARD TIMEOUT after $Timeout s -> killing pid $($p.Id)"
        & taskkill /PID $p.Id /T /F 2>$null | Out-Null
        Start-Sleep -Milliseconds 500
        return 124
    }
    $p.WaitForExit()
    return $p.ExitCode
}

function Needs-Import {
    $stampFile = Join-Path $Proj '.godot\fable_import_stamp'
    if (-not (Test-Path $stampFile)) { return $true }
    $t = (Get-Item $stampFile).LastWriteTimeUtc
    $newer = Get-ChildItem -Path (Join-Path $Proj 'gta') -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.gd', '.glb', '.gltf', '.tscn', '.tres', '.png', '.wav', '.ogg', '.gdshader', '.svg', '.jpg', '.res' -and $_.LastWriteTimeUtc -gt $t } |
        Select-Object -First 1
    if ((Get-Item (Join-Path $Proj 'project.godot')).LastWriteTimeUtc -gt $t) { return $true }
    return [bool]$newer
}

function Run-Import {
    $o = Join-Path $LogDir "$stamp`_import.out.log"; $e = Join-Path $LogDir "$stamp`_import.err.log"
    $stampFile = Join-Path $Proj '.godot\fable_import_stamp'
    $before = Get-Date
    $code = Invoke-Godot @('--headless', '--path', $Proj, '--import') 400 $o $e
    New-Item -ItemType Directory -Force (Join-Path $Proj '.godot') | Out-Null
    Set-Content -Path $stampFile -Value $before.ToString('o') -Encoding ascii
    (Get-Item $stampFile).LastWriteTimeUtc = $before.ToUniversalTime()
    Write-Host "[godot.ps1] import pass exit=$code log=$o"
    return $code
}

$mutex = New-Object System.Threading.Mutex($false, 'Global\FableGTA_Ultracode_Godot_SingleInstance')
$got = $false
try {
    try { $got = $mutex.WaitOne(540000) } catch [System.Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) {
        Write-Output '[godot.ps1] could not acquire the single-instance lock within 9 minutes. Try again later.'
        exit 97
    }
    Stop-StrayGodot

    if ($Mode -eq 'import') {
        $code = Run-Import
        $LogOut = Join-Path $LogDir "$stamp`_import.out.log"; $LogErr = Join-Path $LogDir "$stamp`_import.err.log"
    }
    else {
        if (-not $NoImport -and (Needs-Import)) { [void](Run-Import) }
        $userTail = @()
        if ($UserArgs.Count -gt 0) { $userTail = @('--') + $UserArgs }
        switch ($Mode) {
            'check' {
                $a = @('--headless', '--path', $Proj, '--script', 'res://gta/code/editor/check_all.gd', '--', "--dirs=$Dirs")
                $code = Invoke-Godot $a $TimeoutSec $LogOut $LogErr
            }
            'export' {
                # -Script carries the output path, e.g. build/HalcyonBay.exe (preset "Windows Desktop")
                $outPath = if ($Script -ne '') { $Script } else { 'build/HalcyonBay.exe' }
                New-Item -ItemType Directory -Force (Join-Path $Proj (Split-Path $outPath)) | Out-Null
                $a = @('--headless', '--path', $Proj, '--export-release', 'Windows Desktop', $outPath)
                $code = Invoke-Godot $a $TimeoutSec $LogOut $LogErr
            }
            'script' {
                $a = @('--headless', '--path', $Proj, '--script', $Script) + $userTail
                $code = Invoke-Godot $a $TimeoutSec $LogOut $LogErr
            }
            'headless' {
                $a = @('--headless', '--path', $Proj, '--fixed-fps', '60', '--quit-after', "$Frames")
                if ($Scene -ne '') { $a += $Scene }
                $a += $userTail
                $code = Invoke-Godot $a $TimeoutSec $LogOut $LogErr
            }
            'window' {
                if (-not (Wait-Gpu)) {
                    Write-Output '[godot.ps1] GPU stayed above 85 % for 5 minutes - windowed run skipped. Retry later; do NOT bypass.'
                    exit 96
                }
                $a = @('--path', $Proj, '--windowed', '--resolution', $Res, '--position', '40,40', '--max-fps', "$Fps", '--quit-after', "$Frames")
                if ($Scene -ne '') { $a += $Scene }
                $a += $userTail
                $code = Invoke-Godot $a $TimeoutSec $LogOut $LogErr
            }
        }
    }
    Stop-StrayGodot
}
finally {
    if ($got) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

Write-Output "[godot.ps1] mode=$Mode exit=$code"
Write-Output "[godot.ps1] stdout log: $LogOut"
Write-Output "[godot.ps1] stderr log: $LogErr"
$pattern = 'ERROR|SCRIPT ERROR|Parse Error|Parser Error|WARNING|TEST_RESULT|CHECK_|SHOT_SAVED|device lost|DEVICE_LOST|Failed|Invalid|Cannot|not found|Nonexistent'
$all = @()
if (Test-Path $LogOut) { $all += Get-Content $LogOut }
if (Test-Path $LogErr) { $all += Get-Content $LogErr }
$hits = $all | Where-Object { $_ -match $pattern } | Select-Object -First 80
if ($hits) {
    Write-Output '---- flagged lines (first 80) ----'
    $hits | ForEach-Object { Write-Output $_ }
}
if ($Tail -gt 0 -and (Test-Path $LogOut)) {
    Write-Output "---- stdout tail ($Tail) ----"
    Get-Content $LogOut -Tail $Tail | ForEach-Object { Write-Output $_ }
}
exit $code
