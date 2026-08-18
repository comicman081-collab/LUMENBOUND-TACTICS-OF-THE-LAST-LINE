. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
$project = Join-Path $root 'godot'
Invoke-Checked $godot @(
    '--path', $project,
    '--position', '10000,10000',
    '--resolution', '1920x1080',
    '--disable-vsync',
    'res://tools/capture_visual_qa.tscn'
)
