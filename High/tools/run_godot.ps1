# Hard-limited Godot launcher for validation runs (GPU-safety: one instance, frame cap, timeout, kill on overrun).
param([string]$Test = "boot", [int]$Seconds = 60, [switch]$Headless, [switch]$Import, [string]$Script = "")
$godot = "W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$proj = Split-Path -Parent $PSScriptRoot
$log = Join-Path $proj "tools\_out\godot_$Test.log"
New-Item -ItemType Directory -Force (Join-Path $proj "tools\_out") | Out-Null
if (Get-Process | Where-Object { $_.ProcessName -like "Godot*" -and $_.Path -like "*4.7.2*" -and $_.MainWindowTitle -like "*Marlow*" }) { Write-Output "another Marlow Bay instance is running"; exit 1 }
$gpu = (& nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits) -split ","
$tries = 0
while (([int]$gpu[0] -gt 85 -or ([int]$gpu[1] / [int]$gpu[2]) -gt 0.85) -and $tries -lt 12) { Start-Sleep -Seconds 10; $tries++; $gpu = (& nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits) -split "," }
Write-Output ("GPU before: util {0}% mem {1}/{2} MiB" -f $gpu[0].Trim(), $gpu[1].Trim(), $gpu[2].Trim())
if ($Import) { $args2 = @("--headless", "--path", "`"$proj`"", "--import") }
elseif ($Script -ne "") { $args2 = @("--headless", "--path", "`"$proj`"", "--script", $Script) }
elseif ($Headless) { $args2 = @("--headless", "--path", "`"$proj`"", "--quit-after", ($Seconds * 60), "--", "--autotest=$Test") }
else { $args2 = @("--path", "`"$proj`"", "--resolution", "1280x720", "--max-fps", "60", "--quit-after", ($Seconds * 60), "--", "--autotest=$Test") }
$p = Start-Process -FilePath $godot -ArgumentList $args2 -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru
if (-not $p.WaitForExit($Seconds * 1000 + 15000)) { try { $p.Kill() } catch {}; Write-Output "TIMEOUT: killed Godot" }
Start-Sleep -Milliseconds 300
$out = @(); if (Test-Path $log) { $out += Get-Content $log }; if (Test-Path "$log.err") { $out += Get-Content "$log.err" }
$out | Where-Object { $_ -match "autotest" } | Select-Object -First 70
$out | Where-Object { $_ -match "ERROR|WARNING|Parse Error|DEVICE_LOST|device lost|\[\d\] " -and $_ -notmatch "inconsistent" } | Group-Object | Sort-Object Count -Descending | Select-Object -First 30 | ForEach-Object { "{0,5}x {1}" -f $_.Count, $_.Name }
Write-Output ("exit code: " + $p.ExitCode + "  lines: " + $out.Count)
