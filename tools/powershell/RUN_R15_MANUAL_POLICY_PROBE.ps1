param(
    [ValidateRange(1, 1000)]
    [int]$RunsPerPolicyStage = 200,
    [ValidatePattern('^[A-Za-z0-9_.-]+\.json$')]
    [string]$OutputName = 'R15_MANUAL_POLICY_PAIRED_PROBE.json'
)

. "$PSScriptRoot\COMMON.ps1"

$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
Write-Host "R15 paired manual policy probe: runs/policy/stage=$RunsPerPolicyStage output=$OutputName"
Invoke-Checked $godot @(
    '--headless',
    '--path', (Join-Path $root 'godot'),
    'res://tools/r15_manual_policy_probe.tscn',
    '--',
    "$RunsPerPolicyStage",
    $OutputName
)
