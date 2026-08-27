. "$PSScriptRoot\COMMON.ps1"

$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), 'res://tests/r15_test_runner.tscn')
