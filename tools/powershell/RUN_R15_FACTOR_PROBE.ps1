param(
    [ValidateRange(10, 200)]
    [int]$RunsPerCell = 30
)

. "$PSScriptRoot\COMMON.ps1"

$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), 'res://tools/r15_stage_factor_probe.tscn', '--', "$RunsPerCell")
