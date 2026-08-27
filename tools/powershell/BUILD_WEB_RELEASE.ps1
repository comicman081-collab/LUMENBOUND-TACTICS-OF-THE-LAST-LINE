param(
    [switch]$CompressWasmForLimitedHost
)

. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$godot = Find-Godot471
$python = Find-LocalPython
Set-ProjectGodotUserPaths $root
Copy-GodotWebTemplatesToProjectProfile $root

$dataGenerator = Join-Path $root 'tools\generate_data.py'
$runtimeBuilder = Join-Path $root 'tools\web\build_runtime_combat_packs.py'
$staticValidator = Join-Path $root 'tools\validate_static.py'
$audioBuilder = Join-Path $root 'tools\audio\build_audio_pack.py'
if (-not (Test-Path -LiteralPath $dataGenerator -PathType Leaf)) { throw "Data generator missing: $dataGenerator" }
if (-not (Test-Path -LiteralPath $runtimeBuilder -PathType Leaf)) { throw "Runtime combat pack builder missing: $runtimeBuilder" }
if (-not (Test-Path -LiteralPath $staticValidator -PathType Leaf)) { throw "Static validator missing: $staticValidator" }
if (-not (Test-Path -LiteralPath $audioBuilder -PathType Leaf)) { throw "Audio builder missing: $audioBuilder" }
Invoke-Checked $python @($audioBuilder)
Invoke-Checked $python @($dataGenerator)
Invoke-Checked $python @($runtimeBuilder)
Invoke-Checked $python @($staticValidator)

$buildRoot = [IO.Path]::GetFullPath((Join-Path $root 'builds'))
$output = [IO.Path]::GetFullPath((Join-Path $buildRoot 'web_release'))
$expected = [IO.Path]::GetFullPath((Join-Path $root 'builds\web_release'))
if (-not $output.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to replace an unexpected Web output: $output"
}
if (Test-Path -LiteralPath $output -PathType Container) {
    Remove-Item -LiteralPath $output -Recurse -Force
}
New-Item -ItemType Directory -Path $output -Force | Out-Null

Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), '--export-release', 'Web HTML Release', (Join-Path $output 'index.html'))
if (-not (Test-Path -LiteralPath (Join-Path $output 'index.html') -PathType Leaf)) { throw 'Web HTML Release index.html missing after export.' }

$pck = Join-Path $output 'index.pck'
$pckHash = Get-FileSha256 $pck

$runtimeUsesPako = $false
if ($CompressWasmForLimitedHost) {
    # This compatibility path is only for a host that cannot accept Godot's
    # standard raw WASM member. The normal Web Release must retain Godot's
    # unmodified loader + WASM contract so it runs from an ordinary HTTP server.
    $pako = Join-Path $root 'tools\web\pako_inflate.min.js'
    $compressor = Join-Path $root 'tools\web\compress_web_wasm.py'
    if (-not (Test-Path -LiteralPath $pako -PathType Leaf)) { throw "Web gzip fallback missing: $pako" }
    if (-not (Test-Path -LiteralPath $compressor -PathType Leaf)) { throw "Web WASM compressor missing: $compressor" }
    Copy-Item -LiteralPath $pako -Destination (Join-Path $output 'pako_inflate.min.js') -Force
    Invoke-Checked $python @($compressor, $output)
    $runtimeUsesPako = $true
    Write-Host 'Web limited-host WASM compression: ENABLED'
} else {
    Write-Host 'Web standard WASM delivery: ENABLED'
}
Invoke-Checked $python @((Join-Path $root 'tools\web\instrument_web_soak.py'), $output)

# Keep the existing Godot project name/save namespace stable, but do not expose
# the development suffix in the public browser tab or installed PWA. Apply this
# before the PWA cache hash is calculated so it fingerprints the final files.
$indexPath = Join-Path $output 'index.html'
$indexHtml = Get-Content -LiteralPath $indexPath -Raw
$publicTitleGuard = @'
		<title>LUMENBOUND: TACTICS OF THE LAST LINE</title>
		<script>
			(() => {
				const enforcePublicTitle = () => {
					if (document.title !== 'LUMENBOUND: TACTICS OF THE LAST LINE') document.title = 'LUMENBOUND: TACTICS OF THE LAST LINE';
				};
				window.addEventListener('load', () => {
					enforcePublicTitle();
					const titleNode = document.querySelector('title');
					if (titleNode) new MutationObserver(enforcePublicTitle).observe(titleNode, {
						childList: true, subtree: true, characterData: true
					});
				});
			})();
		</script>
'@
$indexHtml = $indexHtml.Replace("`t`t<title>LUMENBOUND: TACTICS OF THE LAST LINE</title>", $publicTitleGuard.TrimEnd())
if ($indexHtml -notmatch '<title>LUMENBOUND: TACTICS OF THE LAST LINE</title>') {
    throw 'Failed to set the public LUMENBOUND browser title.'
}
Set-Content -LiteralPath $indexPath -Value $indexHtml -Encoding UTF8

$manifestPath = Join-Path $output 'index.manifest.json'
$publicManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$publicManifest.name = 'LUMENBOUND: TACTICS OF THE LAST LINE'
$publicManifest | ConvertTo-Json -Compress -Depth 16 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$workerPath = Join-Path $output 'index.service.worker.js'
$workerText = Get-Content -LiteralPath $workerPath -Raw
$workerText = $workerText.Replace("const CACHE_PREFIX = 'LUMENBOUND: TACT-sw-cache-';", "const CACHE_PREFIX = 'LUMENBOUND-TACTICS-sw-cache-';")
if ($workerText -notmatch "const CACHE_PREFIX = 'LUMENBOUND-TACTICS-sw-cache-';") {
    throw 'Failed to set the public LUMENBOUND service-worker cache prefix.'
}
# Godot's stock worker is cache-first for navigation. That can keep an old
# index.html alive indefinitely at our intentionally stable local release URL.
# Preserve its offline fallback, but make navigation network-first and activate
# a freshly fetched worker immediately. Each template edit is guarded so a
# future Godot template change fails visibly instead of changing cache policy.
$installNeedle = "event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)));"
$installReplacement = "event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)).then(() => self.skipWaiting()));"
if (-not $workerText.Contains($installNeedle)) { throw 'Unexpected Godot service-worker install block; cannot apply safe update policy.' }
$workerText = $workerText.Replace($installNeedle, $installReplacement)

$activateNeedle = "return ('navigationPreload' in self.registration) ? self.registration.navigationPreload.enable() : Promise.resolve();"
$activateReplacement = "return (('navigationPreload' in self.registration) ? self.registration.navigationPreload.enable() : Promise.resolve()).then(() => self.clients.claim());"
if (-not $workerText.Contains($activateNeedle)) { throw 'Unexpected Godot service-worker activate block; cannot apply safe update policy.' }
$workerText = $workerText.Replace($activateNeedle, $activateReplacement)

$navigationPattern = '(?s)\t\t\t\tif \(isNavigate\) \{.*?\n\t\t\t\t\}\n\t\t\t\tlet cached'
$navigationReplacement = @'
				if (isNavigate) {
					// A rebuilt stable URL must obtain the new HTML and register the new
					// worker. Offline launches still use the most recently cached shell.
					try {
						return await fetchAndCache(event, cache, true);
					} catch (e) {
					console.warn('Navigation network error; using cached LUMENBOUND shell.', e); // eslint-disable-line no-console
						return (await cache.match(event.request))
							|| (await cache.match(CACHED_FILES[0]))
							|| (await caches.match(OFFLINE_URL));
					}
				}
				let cached
'@
$navigationWorker = [regex]::Replace($workerText, $navigationPattern, $navigationReplacement, 1)
if ($navigationWorker -eq $workerText) { throw 'Unexpected Godot service-worker navigation block; cannot apply safe update policy.' }
$workerText = $navigationWorker
Set-Content -LiteralPath $workerPath -Value $workerText -Encoding UTF8

# Keep the public R7 filenames fixed while rotating Godot's PWA cache from the
# final post-processed runtime bytes.  The loader URL remains exactly
# `index.js`, matching CACHED_FILES so an installed build still works offline.
$cacheInputNames = @('index.pck', 'index.wasm', 'index.js', 'index.html')
$cacheInputHashes = foreach ($name in $cacheInputNames) {
    Get-FileSha256 (Join-Path $output $name)
}
$cacheBytes = [Text.Encoding]::UTF8.GetBytes(($cacheInputHashes -join '|'))
$cacheHasher = [Security.Cryptography.SHA256]::Create()
try {
    $cacheHash = (($cacheHasher.ComputeHash($cacheBytes) | ForEach-Object { $_.ToString('x2') }) -join '')
} finally {
    $cacheHasher.Dispose()
}
$worker = Get-Content -LiteralPath $workerPath -Raw
$cachePattern = "const CACHE_VERSION = '[^']+';"
$cacheReplacement = "const CACHE_VERSION = 'r7_$($cacheHash.Substring(0, 16))';"
$worker = [regex]::Replace($worker, $cachePattern, $cacheReplacement, 1)
if ($worker -notmatch [regex]::Escape($cacheReplacement)) { throw 'Failed to pin the R7 service-worker cache to the final runtime bytes.' }
if ($worker -notmatch [regex]::Escape('self.skipWaiting()')) { throw 'Updated service worker is missing skipWaiting().' }
if ($worker -notmatch [regex]::Escape('self.clients.claim()')) { throw 'Updated service worker is missing clients.claim().' }
if ($worker -notmatch [regex]::Escape('Navigation network error; using cached LUMENBOUND shell.')) { throw 'Updated service worker is missing network-first navigation fallback.' }
Set-Content -LiteralPath $workerPath -Value $worker -Encoding UTF8

@'
# LUMENBOUND R7 Web MVP

Godot 4.7.1 Compatibility Web export. Serve this directory over HTTP.
The SRPG hex world is Chapter traversal; combat remains the deterministic
real-time five-character SD battle. Mobile landscape and portrait layouts are
supported. Local user-owned audio is enabled after the first trusted input.
Production approval remains pending explicit user review.
'@ | Set-Content -LiteralPath (Join-Path $output 'README_HTML.md') -Encoding UTF8

[ordered]@{
    build_id = 'LUMENBOUND_R7_WEB_MVP'
    engine = 'Godot 4.7.1-stable'
    renderer = 'Compatibility'
    target = 'Web HTML Release'
    revision = 'R7'
    pck_sha256 = $pckHash
    battle_contract = 'deterministic real-time SD battle preserved'
    mobile_orientation = 'landscape_and_portrait'
    production_approved = $false
    created_utc = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'VERSION.json') -Encoding UTF8

$godotLicense = Join-Path (Split-Path -Parent $godot) 'LICENSE.txt'
$fontLicense = Join-Path $root 'godot\assets\fonts\NotoSansKR-OFL.txt'
$licenseSources = @($godotLicense, $fontLicense)
$pakoLicenses = Join-Path $root 'tools\web\PAKO_LICENSES.txt'
if ($runtimeUsesPako) {
    $licenseSources += $pakoLicenses
}
foreach ($licenseSource in $licenseSources) {
    if (-not (Test-Path -LiteralPath $licenseSource -PathType Leaf)) { throw "Required license text missing: $licenseSource" }
}
$publicProjectPolicy = Get-Content -LiteralPath (Join-Path $root 'docs\LICENSE_POLICY.md') -Raw
$publicProjectPolicy = $publicProjectPolicy.Replace(
    '`tools/local_art_pipeline/model_policy.json`',
    '빌드 시점 로컬 모델 허용 목록'
)
$publicProjectPolicy = [regex]::Replace(
    $publicProjectPolicy,
    '`(?i)[A-Z]:\\[^`]+`',
    '로컬 제작 모델 저장소'
)
$licenseSections = @(
    '# LUMENBOUND R7 Web — License Notices',
    '',
    '## Project asset policy',
    '',
    $publicProjectPolicy,
    '',
    '## Godot Engine 4.7.1',
    '',
    (Get-Content -LiteralPath $godotLicense -Raw)
)
if ($runtimeUsesPako) {
    $licenseSections += @(
        '',
        '## pako and embedded zlib-derived code',
        '',
        (Get-Content -LiteralPath $pakoLicenses -Raw)
    )
}
$licenseSections += @(
    '',
    '## Noto Sans KR',
    '',
    (Get-Content -LiteralPath $fontLicense -Raw)
)
$licenseText = $licenseSections -join "`r`n"
$licenseText | Set-Content -LiteralPath (Join-Path $output 'LICENSES.md') -Encoding UTF8

$required = @(
    'index.html', 'index.js', 'index.wasm', 'index.pck', 'index.png',
    'index.manifest.json', 'index.service.worker.js', 'index.offline.html',
    'index.icon.png', 'index.apple-touch-icon.png', 'index.144x144.png',
    'index.180x180.png', 'index.512x512.png', 'index.audio.worklet.js',
    'index.audio.position.worklet.js', 'README_HTML.md', 'VERSION.json',
    'LICENSES.md'
)
foreach ($name in $required) {
    $path = Join-Path $output $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required R7 Web file missing: $path" }
    if ((Get-Item -LiteralPath $path).Length -le 0) { throw "Required R7 Web file empty: $path" }
}

$manifest = Get-Content -LiteralPath (Join-Path $output 'index.manifest.json') -Raw | ConvertFrom-Json
if ($manifest.orientation -ne 'any') { throw "PWA orientation must support landscape and portrait, got: $($manifest.orientation)" }
$runtimeManifestFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'godot\assets\runtime_web') -Recurse -Filter '*.json' -File)
$runtimeManifestPaths = @($runtimeManifestFiles.FullName) + (Join-Path $root 'godot\assets\audio\audio_manifest.json')
$privatePathPattern = 'source_blend|source_path|(?<![A-Za-z0-9_])[A-Za-z]:[\\/]+'
$privatePathLeaks = @(Select-String -LiteralPath $runtimeManifestPaths -Pattern $privatePathPattern)
if ($privatePathLeaks.Count -gt 0) {
    $locations = ($privatePathLeaks | ForEach-Object { "$($_.Path):$($_.LineNumber)" }) -join ', '
    throw "Runtime manifest leaks private authoring lineage: $locations"
}

# The exported PCK and public companion files must not retain Blender lineage,
# render commands, or machine-local authoring paths.  The source manifests stay
# in the repository but are excluded by both Web presets.
$publicLeakPattern = '(?i)(?<![A-Za-z0-9_])[A-Za-z]:[\\/]|source_blends?|render_command|blender_sources|\.blend\b'
$publicTextFiles = @(
    Get-ChildItem -LiteralPath $output -File |
        Where-Object { $_.Extension -in @('.html', '.js', '.json', '.md') } |
        Select-Object -ExpandProperty FullName
)
$publicTextLeaks = @()
if ($publicTextFiles.Count -gt 0) {
    $publicTextLeaks = @(Select-String -LiteralPath $publicTextFiles -Pattern $publicLeakPattern)
}
if ($publicTextLeaks.Count -gt 0) {
    $locations = ($publicTextLeaks | ForEach-Object { "$($_.Path):$($_.LineNumber)" }) -join ', '
    throw "Public Web companion files leak authoring lineage: $locations"
}
$pckUtf8 = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($pck))
$pckLeakPattern = '(?i)source_blends?|render_command|blender_sources|[A-Za-z]:[\\/]{1,2}(?:Users|Program Files)|D:[\\/]{1,2}AI 종합 폴더'
$pckLeak = [regex]::Match($pckUtf8, $pckLeakPattern)
if ($pckLeak.Success) {
    throw "Exported PCK leaks authoring lineage token: $($pckLeak.Value)"
}
Write-Host "Web HTML Release export: $output"
Write-Host "WEB_R7_PCK_SHA256=$pckHash"
