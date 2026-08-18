$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Python = 'C:\AI_ENVS\ComfyUI_windows_portable\python_embeded\python.exe'
$Script = Join-Path $ProjectRoot 'tools\local_art_pipeline\generate_sdxl_depth_role_pilot.py'

if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw "Local inference Python missing: $Python" }
if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) { throw "R07 generator missing: $Script" }

Write-Host "Project: $ProjectRoot"
Write-Host "Python:  $Python"
Write-Host 'Models:  local SDXL Base + local ControlNet Depth (read-only)'
Write-Host 'Policy:  FEMALE_ONLY / ADULT_ONLY / MAXIMUM_NON_EXPLICIT'
& $Python -B $Script @args
if ($LASTEXITCODE -ne 0) { throw "R07 local depth generation failed with exit code $LASTEXITCODE" }
