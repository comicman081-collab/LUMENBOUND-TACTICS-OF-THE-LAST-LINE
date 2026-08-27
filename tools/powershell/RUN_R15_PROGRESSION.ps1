. "$PSScriptRoot\COMMON.ps1"

$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
# The bootstrap is deliberately a thin SceneTree entrypoint. It proves the
# launcher, dynamic runner load, and service-level fresh-save chain separately
# instead of hiding an early stall behind an opaque scene startup.
Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), 'res://tests/progression/r15_fresh_progression_bootstrap.tscn')
