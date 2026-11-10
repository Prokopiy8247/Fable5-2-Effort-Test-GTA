<#
.SYNOPSIS
  Recovery helper for the shared Blender instance (benchmark master file on localhost:9882).
  Use ONLY when Blender MCP calls have been failing for several minutes.

  * If the MCP port answers            -> prints ALIVE and does nothing.
  * If a blender.exe that has OUR master file open is still running but the port is closed
                                      -> prints STUCK and does nothing (report it; never kill it).
  * If no Blender has our file open    -> starts W:\Blender\blender.exe with the master file
                                         (the add-on auto-starts its server on port 9882) and waits.
  A system-wide mutex makes sure only one caller performs the restart.
#>
$ErrorActionPreference = 'Continue'
$Proj = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Blend = Join-Path $Proj 'GodotFable5.2GTAUltracode.blend'
$Blender = 'W:\Blender\blender.exe'
$Port = 9882

function Test-Port {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(1500) -and $c.Connected
        $c.Close()
        return $ok
    } catch { return $false }
}

$mutex = New-Object System.Threading.Mutex($false, 'Global\FableGTA_Ultracode_BlenderRecover')
$got = $false
try {
    try { $got = $mutex.WaitOne(120000) } catch [System.Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { Write-Output 'BUSY: another caller is recovering Blender right now. Retry your MCP call in a minute.'; exit 3 }
    if (Test-Port) { Write-Output "ALIVE: port $Port answers. Retry your MCP call."; exit 0 }
    $ours = Get-CimInstance Win32_Process -Filter "Name = 'blender.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains('GodotFable5.2GTAUltracode.blend') }
    if ($ours) {
        Write-Output "STUCK: Blender (pid $($ours.ProcessId -join ',')) has the master file open but port $Port is closed. It may be busy with a long operation. Wait and retry; if it persists for 10+ minutes report it to the lead. Do NOT kill it."
        exit 2
    }
    Write-Output 'DOWN: no Blender has the master file open. Restarting it ...'
    Start-Process -FilePath $Blender -ArgumentList ('"' + $Blend + '"') -WorkingDirectory $Proj
    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 2
        if (Test-Port) {
            Add-Content -Path (Join-Path $Proj 'qa\logs\blender_recover.log') -Value ("{0} restarted Blender, port {1} up after {2}s" -f (Get-Date -Format o), $Port, ($i * 2))
            Write-Output "RESTARTED: Blender is back on port $Port. Unsaved work since the last G.save() is lost - re-run your asset scripts."
            exit 0
        }
    }
    Write-Output "FAILED: Blender started but port $Port did not open within 90 s. Report to the lead."
    exit 4
}
finally {
    if ($got) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
