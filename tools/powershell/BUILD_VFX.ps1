. "$PSScriptRoot\COMMON.ps1"
$blender = Find-Blender45
$factory = 'D:\AI 종합 폴더\Games\asset_share'
$revision = if ($args.Count -gt 0) { $args[0] } else { 'R5' }
$root = Join-Path $factory "exports\premium\pilot\$revision"
Invoke-Checked $blender @('--background', '--python', (Join-Path $factory 'blender\premium\build_vfx.py'), '--', '--root', $root, '--revision', $revision)
