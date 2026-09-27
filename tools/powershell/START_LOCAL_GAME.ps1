param(
    [ValidateRange(1024, 65535)][int]$Port = 8770,
    [switch]$NoBrowser,
    [switch]$Intro
)
. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$buildName = 'builds/web_tactics_r14_release'
$build = Join-Path $root $buildName
$health = "http://127.0.0.1:$Port/__local_game_status"

function Get-LocalPlayer {
    try { return Invoke-RestMethod -Uri $health -TimeoutSec 2 }
    catch { return $null }
}
function Test-LocalPlayer($status) {
    return $null -ne $status -and $status.service -eq 'lumenbound-local-player-v2' -and $status.build -eq $buildName
}

$status = Get-LocalPlayer
if (-not (Test-LocalPlayer $status)) {
    # After the verified build changes, the previous build's launcher server may
    # still be running. Replace only our own server; never stop another service.
    if ($null -ne $status -and $status.service -eq 'lumenbound-local-player-v2' -and $status.pid) {
        Write-Host "Replacing local server for $($status.build) (PID $($status.pid))."
        Stop-Process -Id ([int]$status.pid) -ErrorAction SilentlyContinue
        for ($attempt=0; $attempt -lt 20 -and (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue); $attempt++) {
            Start-Sleep -Milliseconds 250
        }
        $status = $null
    }
    if ($null -ne $status) { throw "Another service is using port $Port." }
    if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) {
        throw "Port $Port is already occupied. Choose a free port; no second server was started."
    }
    $python = Find-LocalPython
    Invoke-Checked $python @((Join-Path $root 'tools\web\stage_density_sidecars.py'), $build, '--validate-only')
    Invoke-Checked $python @((Join-Path $root 'tools\web\stage_audio_sidecars.py'), $build, '--validate-only')
    $logs = Join-Path $root 'reports\local_launcher'
    $scratch = Join-Path $logs 'tmp'
    New-Item -ItemType Directory -Force -Path $logs,$scratch | Out-Null
    $stamp = '{0}-{1}' -f $PID,[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $serverScript = Join-Path $root 'tools\web\serve_local_game.py'
    $env:TEMP = $scratch
    $env:TMP = $scratch
    $env:PYTHONDONTWRITEBYTECODE = '1'
    # WMI creates the server outside the launching terminal's process job.
    # A hidden Start-Process child was still terminated with an interrupted task.
    $logFile = Join-Path $logs "$stamp.server.log"
    $startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
    $commandLine = '"{0}" -B -u "{1}" --build "{2}" --port {3} --log-file "{4}"' -f $python,$serverScript,$build,$Port,$logFile
    $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = $commandLine
        CurrentDirectory = $root
        ProcessStartupInformation = $startup
    }
    if ($created.ReturnValue -ne 0) { throw "Local server process creation failed: $($created.ReturnValue)" }
    $serverPid = [int]$created.ProcessId
    $ready = $false
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 250
        $status = Get-LocalPlayer
        if (Test-LocalPlayer $status) { $ready=$true; break }
        if (-not (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)) { break }
    }
    if (-not $ready) {
        Stop-Process -Id $serverPid -ErrorAction SilentlyContinue
        throw "Local game could not start. Inspect $logFile"
    }
}
$url = "http://127.0.0.1:$Port$($status.play_path)"
if ($Intro) { $url = "http://127.0.0.1:$Port/intro-preview" }
Write-Host "LOCAL_GAME_READY $url (server PID $($status.pid))"
if (-not $NoBrowser) { Start-Process $url }
