param(
    [ValidateRange(1, 1000)]
    [int]$Runs = 100
)

. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
Invoke-Checked $godot @(
    '--headless',
    '--path', (Join-Path $root 'godot'),
    'res://tools/simulate_battles.tscn',
    '--', [string]$Runs
)
