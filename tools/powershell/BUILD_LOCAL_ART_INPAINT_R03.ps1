. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$python = 'C:\AI_ENVS\ComfyUI_windows_portable\python_embeded\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw "로컬 추론 Python 누락: $python"
}
$model = 'C:\AI_MODELS\sdxl-inpaint'
if (-not (Test-Path -LiteralPath (Join-Path $model 'model_index.json') -PathType Leaf)) {
    throw "승인 SDXL Inpaint 모델 누락: $model"
}
$output = Join-Path $root 'work\art_gen\sdxl_inpaint_pilot_r03'
Write-Host '승인된 로컬 SDXL Inpaint만 사용하며 모델 원본은 수정·이동·삭제하지 않습니다.'
Write-Host '모든 캐릭터 작업은 프로젝트 전역 FEMALE_ONLY 정책을 통과해야 합니다.'
Invoke-Checked $python @('-B', (Join-Path $root 'tools\local_art_pipeline\refine_sdxl_inpaint_pilot.py'), '--output', $output)
