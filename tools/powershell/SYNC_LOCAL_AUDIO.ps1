[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\COMMON.ps1"
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$builder = Join-Path $projectRoot 'tools\audio\build_audio_pack.py'
if (-not (Test-Path -LiteralPath $builder)) { throw "Audio builder missing: $builder" }
$python = Find-LocalPython
Write-Host "LOCAL_AUDIO_SOURCE=$(Join-Path (Split-Path -Parent $projectRoot) 'Sound')"
Write-Host "AUDIO_BUILDER=$builder"
Write-Host "AUDIO_PYTHON=$python"
& $python $builder
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$manifest = Join-Path $projectRoot 'godot\assets\audio\audio_manifest.json'
if (-not (Test-Path -LiteralPath $manifest)) { throw "Runtime audio manifest was not produced: $manifest" }
Write-Host "AUDIO_SYNC_STATUS=PASS"
