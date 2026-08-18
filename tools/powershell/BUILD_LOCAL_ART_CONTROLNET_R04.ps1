. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$python = 'C:\AI_ENVS\ComfyUI_windows_portable\python_embeded\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw "로컬 추론 Python 누락: $python"
}
$base = 'C:\AI_MODELS\sdxl-base-1.0'
$control = 'C:\AI_MODELS\controlnet-sdxl\controlnet-canny-sdxl-1.0'
if (-not (Test-Path -LiteralPath (Join-Path $base 'LICENSE.md') -PathType Leaf)) {
    throw "승인 SDXL Base 라이선스 누락: $base"
}
if (-not (Test-Path -LiteralPath (Join-Path $control 'config.json') -PathType Leaf)) {
    throw "승인 ControlNet Canny 모델 누락: $control"
}
$output = Join-Path $root 'work\art_gen\sdxl_controlnet_pilot_r04'
Write-Host '프로젝트가 직접 작성한 형상 가이드와 승인된 로컬 SDXL/ControlNet Canny만 사용합니다.'
Write-Host '모델 원본은 읽기 전용이며 모든 캐릭터 생성은 FEMALE_ONLY입니다.'
Invoke-Checked $python @('-B', (Join-Path $root 'tools\local_art_pipeline\refine_sdxl_controlnet_pilot.py'), '--output', $output)
