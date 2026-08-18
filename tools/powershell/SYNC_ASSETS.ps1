. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$python = Find-LocalPython
Invoke-Checked $python @((Join-Path $root 'tools\asset_bridge\sync_assets.py'))
$godot = $null
try { $godot = Find-Godot471 } catch { Write-Warning $_.Exception.Message }
if ($godot) {
    Set-ProjectGodotUserPaths $root
    Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), '--script', 'res://tools/validate_asset_manifest.gd')
}
