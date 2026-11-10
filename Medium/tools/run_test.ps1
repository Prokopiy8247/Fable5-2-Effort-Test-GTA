# Time-limited, frame-capped Godot test runner (GPU-safe). Usage: tools\run_test.ps1 <scenario> [-Headless] [-Seconds 110]
param([string]$Scenario = "world", [switch]$Headless, [int]$Seconds = 115, [switch]$Import)
$g = "W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$root = Split-Path -Parent $PSScriptRoot
# GPU back-off: wait while the shared GPU is busy
for ($i = 0; $i -lt 12; $i++) {
    $q = (nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits) -split ','
    if ([int]$q[0] -lt 85 -and ([int]$q[1] / [int]$q[2]) -lt 0.85) { break }
    Start-Sleep -Seconds 15
}
if (Get-Process | Where-Object { $_.ProcessName -like 'Godot*' -and $_.MainWindowTitle -like '*Port Cinder*' }) { "another instance of this project is running"; exit 3 }
$log = Join-Path $env:TEMP "gta_medium_$Scenario.log"
$err = Join-Path $env:TEMP "gta_medium_${Scenario}_err.log"
if ($Import) { $a = @('--headless', '--path', "`"$root`"", '--import') }
elseif ($Headless) { $a = @('--headless', '--path', "`"$root`"", '--', "--test=$Scenario") }
else { $a = @('--path', "`"$root`"", '--resolution', '1280x720', '--position', '40,40', '--max-fps', '60', '--', "--test=$Scenario") }
$p = Start-Process -FilePath $g -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
if (-not $p.WaitForExit($Seconds * 1000)) { $p.Kill(); "TIMEOUT - killed" }
Get-Content $log | Select-String -Pattern '^\[TEST\]|^\[main\]|^\[PERF\]' | Select-Object -First 70 | ForEach-Object { $_.Line }
# de-duplicated script errors with their first location line
$lines = Get-Content $err
$seen = @{}
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'SCRIPT ERROR|^ERROR|Parse Error|WARNING: .*leak') {
        $key = $lines[$i] + ' | ' + $(if ($i + 1 -lt $lines.Count) { $lines[$i + 1].Trim() } else { '' })
        if (-not $seen.ContainsKey($key)) { $seen[$key] = 1 } else { $seen[$key]++ }
    }
}
$seen.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 25 | ForEach-Object { "x$($_.Value)  $($_.Key)" }
