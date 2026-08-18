. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$python = Find-LocalPython
$version = '4.7.1.stable'
$destination = Join-Path $env:APPDATA "Godot\export_templates\$version"
$manifest = Join-Path $destination 'LANTERNLINE_WEB_TEMPLATE_MANIFEST.json'
$installer = Join-Path $root 'tools\install_godot_web_templates.py'
Write-Host "Godot Web template destination: $destination"
Write-Host 'Only official Web template ZIP entries are fetched; no native game build is created.'
Invoke-Checked $python @('-B', $installer, '--destination', $destination, '--manifest', $manifest)
