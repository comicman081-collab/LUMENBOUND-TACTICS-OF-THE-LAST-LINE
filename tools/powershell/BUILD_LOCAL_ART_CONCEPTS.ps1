. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$python = 'C:\AI_ENVS\ComfyUI_windows_portable\python_embeded\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw "로컬 추론 Python 누락: $python"
}
$model = 'C:\AI_MODELS\sdxl-base-1.0'
if (-not (Test-Path -LiteralPath (Join-Path $model 'LICENSE.md') -PathType Leaf)) {
    throw "승인 모델 라이선스 누락: $model\LICENSE.md"
}
Write-Host '모델 원본은 읽기 전용으로 사용하며 수정·이동·삭제하지 않습니다.'
Write-Host "선택 모델: $model"
$output = Join-Path $root 'work\art_gen\sdxl_policy_pilot_r05'
Invoke-Checked $python @('-B', (Join-Path $root 'tools\local_art_pipeline\generate_sdxl_pilot_concepts.py'), '--model', $model, '--output', $output, '--count', '2')
