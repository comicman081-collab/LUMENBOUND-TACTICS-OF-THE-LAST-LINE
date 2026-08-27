param(
    [ValidateRange(1, 1000)]
    [int]$Runs = 200
)

. "$PSScriptRoot\COMMON.ps1"

$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), 'res://tools/r15_h05_paired_probe.tscn', '--', "$Runs", 'R15_H05_PAIRED_ULTIMATE_POLICY_PROBE.json')
