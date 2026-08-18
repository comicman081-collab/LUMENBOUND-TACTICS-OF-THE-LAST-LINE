. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
Invoke-Checked $godot @('--editor', '--path', (Join-Path $root 'godot'))
