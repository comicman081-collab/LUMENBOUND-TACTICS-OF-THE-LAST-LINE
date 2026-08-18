. "$PSScriptRoot\COMMON.ps1"
$project = Get-ProjectRoot
$godot = Find-Godot471
$runs = if ($args.Count -gt 0) { [int]$args[0] } else { 200 }
$output = if ($args.Count -gt 1) { [string]$args[1] } else { 'before_matrix.json' }
if ($runs -lt 1 -or $runs -gt 1000) { throw "Runs per cell must be 1..1000" }
$runtime = Join-Path $project 'godot\.runtime_profile'
$env:APPDATA = Join-Path $runtime 'Roaming'
$env:LOCALAPPDATA = Join-Path $runtime 'Local'
Invoke-Checked $godot @(
    '--headless',
    '--path', (Join-Path $project 'godot'),
    'res://tools/balance_hardening_matrix.tscn',
    '--', [string]$runs, $output
)
