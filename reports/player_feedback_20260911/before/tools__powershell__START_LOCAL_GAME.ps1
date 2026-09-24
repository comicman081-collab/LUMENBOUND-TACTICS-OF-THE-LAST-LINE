param(
    [ValidateRange(1024, 65535)][int]$Port = 8770,
    [switch]$NoBrowser,
    [switch]$Intro
)
. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$buildName = 'builds/web_intro_1080p_20260910_release'
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
    if ($null -ne $status) { throw "Another service is using port $Port." }
    $python = Find-LocalPython
    Invoke-Checked $python @((Join-Path $root 'tools\web\stage_density_sidecars.py'), $build, '--validate-only')
    $logs = Join-Path $root 'reports\local_launcher'
    $scratch = Join-Path $logs 'tmp'
    New-Item -ItemType Directory -Force -Path $logs,$scratch | Out-Null
    $stamp = '{0}-{1}' -f $PID,[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $serverScript = Join-Path $root 'tools\web\serve_local_game.py'
    $env:TEMP = $scratch
    $env:TMP = $scratch
    $env:PYTHONDONTWRITEBYTECODE = '1'
    # Detached from this launcher/console; logs are files, never closed PTY pipes.
    $server = Start-Process -FilePath $python -ArgumentList @('-u',('"{0}"' -f $serverScript),'--build',('"{0}"' -f $build),'--port',"$Port") -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs "$stamp.stdout.log") -RedirectStandardError (Join-Path $logs "$stamp.stderr.log") -PassThru
    $ready = $false
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 250
        $status = Get-LocalPlayer
        if (Test-LocalPlayer $status) { $ready=$true; break }
        if ($server.HasExited) { break }
    }
    if (-not $ready) { throw "Local game could not start. Inspect $logs\$stamp.stderr.log" }
}
$url = "http://127.0.0.1:$Port$($status.play_path)"
if ($Intro) { $url = "http://127.0.0.1:$Port/intro-preview" }
Write-Host "LOCAL_GAME_READY $url (server PID $($status.pid))"
if (-not $NoBrowser) { Start-Process $url }
