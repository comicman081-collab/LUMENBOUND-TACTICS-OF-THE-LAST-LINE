. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
$project = Join-Path $root 'godot'

try {
    $captureErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Invoke-Checked $godot @(
        '--path', $project,
        '--position', '10000,10000',
        '--resolution', '390x844',
        '--disable-vsync',
        'res://tools/capture_mobile_progression_qa.tscn'
    )
} finally {
    $ErrorActionPreference = $captureErrorPreference
}
