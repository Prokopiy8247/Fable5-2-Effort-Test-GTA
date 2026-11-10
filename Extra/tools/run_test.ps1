# Runs one automated QA scenario with a hard time limit and GPU-load guard.
# Usage: tools\run_test.ps1 -Test world [-Frames 900] [-Headless] [-TimeoutSec 150]
param(
    [string]$Test = "",
    [int]$Frames = 900,
    [switch]$Headless,
    [switch]$Import,
    [int]$TimeoutSec = 150,
    [int]$Tail = 40
)
$godot = "W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$proj = Split-Path -Parent $PSScriptRoot
Set-Location $proj
New-Item -ItemType Directory -Force "_qa" | Out-Null
if (-not $Headless -and -not $Import) {
    for ($i = 0; $i -lt 12; $i++) {
        $q = (& nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits) -split ","
        $util = [int]$q[0]; $mem = [int]$q[1] / [int]$q[2] * 100
        if ($util -lt 85 -and $mem -lt 85) { break }
        Write-Output "GPU busy (util $util%, vram $([int]$mem)%), waiting..."
        Start-Sleep -Seconds 15
    }
}
if (Get-Process -Name "Godot_v4.7.2-stable_win64*" -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.MainWindowTitle -match "Cinder Bay" }) {
    Write-Output "Another Cinder Bay instance is running; aborting."; exit 1
}
$cache = ".godot\global_script_class_cache.cfg"
if (-not $Import) {
    $newest = Get-ChildItem gta -Recurse -Include *.gd,*.glb | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not (Test-Path $cache) -or $newest.LastWriteTime -gt (Get-Item $cache).LastWriteTime) {
        $ip = Start-Process -FilePath $godot -ArgumentList @("--headless", "--path", ".", "--import") -PassThru -NoNewWindow -RedirectStandardOutput "_qa\scan.log" -RedirectStandardError "_qa\scan.log.err"
        if (-not $ip.WaitForExit(180000)) { try { $ip.Kill() } catch {} }
        (Get-Item $cache).LastWriteTime = Get-Date
        Get-Content "_qa\scan.log.err" -ErrorAction SilentlyContinue | Where-Object { $_ -match "Parse Error|SCRIPT ERROR" } | Select-Object -First 12
    }
}
$log = "_qa\run_$($Test)$(if($Import){'import'}).log"
if ($Import) {
    $argList = @("--headless", "--path", ".", "--import")
} elseif ($Headless) {
    $argList = @("--headless", "--path", ".", "--quit-after", "$Frames", "--", "--test=$Test")
} else {
    $argList = @("--path", ".", "--resolution", "1280x720", "--position", "40,40", "--quit-after", "$Frames", "--", "--test=$Test")
}
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $godot -ArgumentList $argList -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError "$log.err"
if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    try { $p.Kill() } catch {}
    Write-Output "TIMEOUT after $TimeoutSec s - process killed"
}
$sw.Stop()
Write-Output ("exit={0} time={1:n1}s" -f $p.ExitCode, $sw.Elapsed.TotalSeconds)
$all = @()
if (Test-Path $log) { $all += Get-Content $log }
if (Test-Path "$log.err") { $all += Get-Content "$log.err" }
$bad = $all | Where-Object { $_ -match "ERROR|SCRIPT ERROR|Parse Error|WARNING|error|Invalid|null instance|\[test\]|\[main\]|at: " } | Select-Object -Unique
$bad | Select-Object -First $Tail
