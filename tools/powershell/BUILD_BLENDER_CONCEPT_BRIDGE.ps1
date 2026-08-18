. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$blender = 'C:\Program Files\Blender Foundation\Blender 4.5\blender.exe'
if (-not (Test-Path -LiteralPath $blender -PathType Leaf)) {
    throw "Blender 4.5 실행 파일 누락: $blender"
}
$manifest = Join-Path $root 'tools\premium_asset_factory\concept_inputs\concept_bridge_manifest.json'
$script = Join-Path $root 'tools\premium_asset_factory\blender\premium\import_concept_guides.py'
$output = Join-Path $root 'tools\premium_asset_factory\blender_sources\premium\concept_guides\PILOT_CONCEPT_GUIDES_REFERENCE_ONLY.blend'
Write-Host 'SDXL 결과는 Blender 모델링 참조로만 연결하며 최종 렌더로 사용하지 않습니다.'
Invoke-Checked $blender @('--background', '--factory-startup', '--python', $script, '--', '--manifest', $manifest, '--output', $output)
