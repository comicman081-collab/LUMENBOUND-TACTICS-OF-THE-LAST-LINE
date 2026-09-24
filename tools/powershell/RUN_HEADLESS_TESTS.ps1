. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
if (-not (Test-Path -LiteralPath (Join-Path $root 'godot/.godot/global_script_class_cache.cfg'))) {
    Invoke-Checked $godot @('--headless', '--editor', '--path', (Join-Path $root 'godot'), '--import', '--quit')
}
Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), 'res://tests/test_runner.tscn')
