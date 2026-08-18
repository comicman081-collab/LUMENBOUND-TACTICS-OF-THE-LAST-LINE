. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$python = Find-LocalPython
$script = Join-Path $root 'tools\install_godot_windows_templates.py'
$destination = Join-Path $env:APPDATA 'Godot\export_templates\4.7.1.stable'
$manifest = Join-Path $destination 'LANTERNLINE_WINDOWS_TEMPLATE_MANIFEST.json'

Write-Host "Python: $python"
Write-Host "Official Windows template destination: $destination"
& $python -B $script --destination $destination --manifest $manifest
if ($LASTEXITCODE -ne 0) { throw "Godot Windows template installer exit code: $LASTEXITCODE" }
