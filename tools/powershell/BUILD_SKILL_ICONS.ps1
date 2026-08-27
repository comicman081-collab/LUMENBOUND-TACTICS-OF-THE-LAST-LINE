. "$PSScriptRoot\COMMON.ps1"

$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), '--script', 'res://tools/build_skill_icons.gd')
# PNGs are emitted after the project filesystem scan.  Run one background
# editor import so ResourceLoader and the Web exporter see every new derivative
# on the very next test/build invocation.
Invoke-Checked $godot @('--headless', '--editor', '--path', (Join-Path $root 'godot'), '--import')
