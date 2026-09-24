$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/COMMON.ps1"
$root = Get-ProjectRoot
$python = Find-LocalPython
Set-ProjectGodotUserPaths $root
Copy-GodotWebTemplatesToProjectProfile $root
$release = Join-Path $root 'builds/web_sites_20260920_release'
$report = Join-Path $root 'reports/sites_update_20260920'
$source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'BUILD_WEB_R7.ps1'))
$start = $source.IndexOf('function ConvertTo-HashedR7RuntimeArtifacts(')
$end = $source.IndexOf('foreach ($directory in @($development, $release))', $start)
. ([scriptblock]::Create($source.Substring($start, $end - $start)))
$godot = Find-Godot471
$exportPresets = Join-Path $root 'godot/export_presets.cfg'
$exportPresetsOriginal = [IO.File]::ReadAllText($exportPresets)
$releasePresetStart = $exportPresetsOriginal.IndexOf('[preset.1]')
$releasePresetEnd = $exportPresetsOriginal.IndexOf('[preset.1.options]')
if ($releasePresetStart -lt 0 -or $releasePresetEnd -le $releasePresetStart) { throw 'Web HTML Release preset section was not found.' }
$releaseSection = $exportPresetsOriginal.Substring($releasePresetStart, $releasePresetEnd - $releasePresetStart)
$releaseSection = [regex]::Replace($releaseSection, '(?m)^exclude_filter="([^"]*)"\r?$', {
    param($match)
    $value = $match.Groups[1].Value
    if ($value -notlike '*res://assets/video/lumenbound_intro_full.ogv*') { $value += ',res://assets/video/lumenbound_intro_full.ogv' }
    'exclude_filter="' + $value + '"'
}, 1)
if ($releaseSection -notlike '*res://assets/video/lumenbound_intro_full.ogv*') { throw 'Failed to add the native intro duplicate to the Sites release exclusion.' }
$exportPresetsPatched = $exportPresetsOriginal.Substring(0, $releasePresetStart) + $releaseSection + $exportPresetsOriginal.Substring($releasePresetEnd)
try {
	[IO.File]::WriteAllText($exportPresets, $exportPresetsPatched, [Text.UTF8Encoding]::new($false))
	& $godot --headless --path (Join-Path $root 'godot') --export-release 'Web HTML Release' (Join-Path $release 'index.html') *> (Join-Path $report 'export.log')
} finally {
	[IO.File]::WriteAllText($exportPresets, $exportPresetsOriginal, [Text.UTF8Encoding]::new($false))
}
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath (Join-Path $report 'export.log') -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) { throw 'Release export failed; see export.log' }
$artifacts = ConvertTo-HashedR7RuntimeArtifacts $release
Invoke-Checked $python @('-B', (Join-Path $root 'tools/web/stage_density_sidecars.py'), $release)
Invoke-Checked $python @('-B', (Join-Path $root 'tools/web/stage_audio_sidecars.py'), $release)
$compressor = Join-Path $root 'tools/web/compress_web_wasm.py'
$pako = Join-Path $root 'tools/web/pako_inflate.min.js'
if (-not (Test-Path -LiteralPath $compressor -PathType Leaf)) { throw "Web WASM compressor missing: $compressor" }
if (-not (Test-Path -LiteralPath $pako -PathType Leaf)) { throw "Web gzip fallback missing: $pako" }
Copy-Item -LiteralPath $pako -Destination (Join-Path $release 'pako_inflate.min.js') -Force
Invoke-Checked $python @('-B', $compressor, $release)
Copy-Item -LiteralPath (Join-Path $root 'work/video/intro_1080p_50s_20260920/intro_1080p_50s_with_existing_bgm_compressed.mp4') -Destination (Join-Path $release 'intro.mp4')
$artifacts | ConvertTo-Json | Set-Content (Join-Path $release 'VERSION.json') -Encoding utf8
Copy-Item -LiteralPath (Join-Path $root 'docs/LICENSE_POLICY.md') -Destination (Join-Path $release 'LICENSES.md')
Write-Output 'SITES_RELEASE_READY'
