. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$python = 'C:\AI_ENVS\ComfyUI_windows_portable\python_embeded\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw "Local image Python missing: $python" }
$script = Join-Path $root 'tools\local_art_pipeline\generate_sdxl_chibi_guardian_r11.py'
Invoke-Checked $python @('-B', $script)
