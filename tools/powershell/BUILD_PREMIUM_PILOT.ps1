. "$PSScriptRoot\COMMON.ps1"
$blender = Find-Blender45
$factory = 'D:\AI 종합 폴더\Games\asset_share'
$script = Join-Path $factory 'blender\premium\premium_pipeline.py'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw "Premium pipeline missing: $script" }
$revision = if ($args.Count -gt 0) { $args[0] } else { 'R5' }
Invoke-Checked $blender @('--background', '--python', $script, '--', '--revision', $revision)
