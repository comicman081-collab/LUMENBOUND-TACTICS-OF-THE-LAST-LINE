. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$godot = Find-Godot471
Copy-GodotWebTemplatesToProjectProfile $root
Set-ProjectGodotUserPaths $root

$development = Join-Path $root 'builds\web_art_pilot_development_r2'
$release = Join-Path $root 'builds\web_art_pilot_release_r2'
foreach ($directory in @($development, $release)) {
    if (Test-Path -LiteralPath $directory -PathType Container) {
        $existing = @(Get-ChildItem -LiteralPath $directory -Force)
        if ($existing.Count -gt 0) { throw "Refusing to overwrite non-empty pilot build directory: $directory" }
    }
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), '--export-debug', 'Web Development', (Join-Path $development 'index.html'))
Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), '--export-release', 'Web HTML Release', (Join-Path $release 'index.html'))

$readme = @'
# LANTERNLINE Web Art Pilot

Serve this directory through a local HTTP server. Opening `index.html` directly is unsupported because browsers restrict WASM and PCK loading from local files.

The runtime is an offline-capable Godot 4.7.1 Web export using the Compatibility renderer. Production approval remains pending user review.
'@
Set-Content -LiteralPath (Join-Path $release 'README_HTML.md') -Value $readme -Encoding UTF8
$version = [ordered]@{
    build_id = 'LANTERNLINE_PREMIUM_ART_PILOT_R5P2'
    engine = 'Godot 4.7.1-stable'
    renderer = 'Compatibility'
    target = 'Web HTML Release'
    art_revision = 'R5'
    production_approved = $false
    created_utc = [DateTime]::UtcNow.ToString('o')
}
$version | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $release 'VERSION.json') -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $root 'docs\LICENSE_POLICY.md') -Destination (Join-Path $release 'LICENSES.md')

$required = @(
    'index.html', 'index.js', 'index.wasm', 'index.pck', 'index.png',
    'index.manifest.json', 'index.service.worker.js', 'index.offline.html',
    'README_HTML.md', 'VERSION.json', 'LICENSES.md'
)
foreach ($name in $required) {
    $path = Join-Path $release $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required Web release file missing: $path" }
    if ((Get-Item -LiteralPath $path).Length -le 0) { throw "Required Web release file empty: $path" }
}
Write-Host "WEB_ART_PILOT_DEVELOPMENT=$development"
Write-Host "WEB_ART_PILOT_RELEASE=$release"
