. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$python = Find-LocalPython
Invoke-Checked $python @((Join-Path $root 'tools\generate_data.py'))
Invoke-Checked $python @((Join-Path $root 'tools\validate_static.py'))
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), 'res://tests/test_runner.tscn')
