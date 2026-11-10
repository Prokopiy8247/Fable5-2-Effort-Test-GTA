# Refreshes the class cache and reports every GDScript parse error in one pass.
param([int]$Max = 60)
$godot = "W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
Set-Location (Split-Path -Parent $PSScriptRoot)
New-Item -ItemType Directory -Force "_qa" | Out-Null
$p = Start-Process -FilePath $godot -ArgumentList @("--headless", "--path", ".", "--import") -PassThru -NoNewWindow -RedirectStandardOutput "_qa\scan.log" -RedirectStandardError "_qa\scan.log.err"
if (-not $p.WaitForExit(180000)) { try { $p.Kill() } catch {} }
$p = Start-Process -FilePath $godot -ArgumentList @("--headless", "--path", ".", "-s", "tools/check_all.gd") -PassThru -NoNewWindow -RedirectStandardOutput "_qa\check.log" -RedirectStandardError "_qa\check.log.err"
if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch {} }
$lines = @(Get-Content "_qa\check.log.err" -ErrorAction SilentlyContinue) + @(Get-Content "_qa\check.log" -ErrorAction SilentlyContinue)
$out = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if ($l -match "Parse Error|Compile Error" -and $l -notmatch "Identifier not found: (G|Assets|Sfx|Save)$|Failed to compile depended") {
        $loc = ""
        if ($i + 1 -lt $lines.Count -and $lines[$i + 1] -match "\((res://[^)]+)\)") { $loc = $Matches[1] }
        $out.Add(($l -replace "SCRIPT ERROR: ", "") + "  @ " + ($loc -replace "res://gta/code/", ""))
    } elseif ($l -match "^checked") { $out.Add($l) }
}
$out | Select-Object -Unique | Select-Object -First $Max
