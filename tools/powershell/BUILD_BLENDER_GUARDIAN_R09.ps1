. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$blender = 'C:\Program Files\Blender Foundation\Blender 4.5\blender.exe'
if (-not (Test-Path -LiteralPath $blender -PathType Leaf)) { throw "Blender 4.5 missing: $blender" }
$version = (& $blender --version | Select-Object -First 1)
if ($version -notmatch '^Blender 4\.5\.') { throw "Pinned Blender 4.5 required, found: $version" }
$script = Join-Path $root 'tools\premium_asset_factory\blender\premium\build_guardian_sd_r09.py'
Invoke-Checked $blender @('--background', '--factory-startup', '--python', $script, '--', '--project-root', $root)
