param([string]$Revision = 'R7')
. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$blender = Find-Blender45
$script = Join-Path $root 'tools\asset_bridge\premium_chapter_map\chapter_map_pipeline.py'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw "Project R7 map pipeline missing: $script" }
Invoke-Checked $blender @('--background', '--python', $script, '--', '--project-root', $root, '--revision', $Revision)
