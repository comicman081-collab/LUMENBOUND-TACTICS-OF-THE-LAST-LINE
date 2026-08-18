$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Python = 'C:\AI_ENVS\ComfyUI_windows_portable\python_embeded\python.exe'
$Script = Join-Path $ProjectRoot 'tools\local_art_pipeline\generate_sdxl_ip_depth_pilot_r08.py'
$LogDir = Join-Path $ProjectRoot 'work\art_gen\logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw "Local inference Python missing: $Python" }
if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) { throw "R08 generator missing: $Script" }

Write-Host "Project: $ProjectRoot"
Write-Host 'Models: local SDXL Base + Depth ControlNet + IP-Adapter (read-only)'
Write-Host 'Policy: FEMALE_ONLY / ADULT_ONLY / MAXIMUM_NON_EXPLICIT / Krea2 excluded'
& $Python -B $Script @args
if ($LASTEXITCODE -ne 0) { throw "R08 generation failed with exit code $LASTEXITCODE" }
