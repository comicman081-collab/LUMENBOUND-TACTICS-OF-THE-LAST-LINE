. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$godot = Find-Godot471
Copy-GodotWebTemplatesToProjectProfile $root
Set-ProjectGodotUserPaths $root
$output = Join-Path $root 'builds\web_release'
New-Item -ItemType Directory -Path $output -Force | Out-Null
Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), '--export-release', 'Web HTML Release', (Join-Path $output 'index.html'))
if (-not (Test-Path -LiteralPath (Join-Path $output 'index.html') -PathType Leaf)) { throw 'Web HTML Release index.html missing after export.' }
Write-Host "Web HTML Release export: $output"
