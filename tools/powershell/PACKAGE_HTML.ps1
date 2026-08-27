. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$source = Join-Path $root 'builds\web_release'
$target = Join-Path $root 'builds\SD_STORY_RPG_HTML.zip'
$required = @(
    'index.html', 'index.js', 'index.wasm', 'index.pck', 'index.png',
    'index.manifest.json', 'index.service.worker.js', 'index.offline.html',
    'index.icon.png', 'index.apple-touch-icon.png', 'index.144x144.png',
    'index.180x180.png', 'index.512x512.png', 'index.audio.worklet.js',
    'index.audio.position.worklet.js', 'README_HTML.md', 'VERSION.json',
    'LICENSES.md'
)
foreach ($name in $required) {
    $path = Join-Path $source $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required Web release member missing: $path" }
    if ((Get-Item -LiteralPath $path).Length -le 0) { throw "Required Web release member empty: $path" }
}
$actualFiles = @(Get-ChildItem -LiteralPath $source -Force -File)
$unexpectedFiles = @($actualFiles | Where-Object { $required -notcontains $_.Name })
$unexpectedDirectories = @(Get-ChildItem -LiteralPath $source -Force -Directory)
if ($unexpectedFiles.Count -gt 0 -or $unexpectedDirectories.Count -gt 0) {
    $unexpectedNames = @($unexpectedFiles.Name) + @($unexpectedDirectories.Name)
    throw "Refusing non-runtime Web members: $($unexpectedNames -join ', ')"
}
$version = Get-Content -LiteralPath (Join-Path $source 'VERSION.json') -Raw | ConvertFrom-Json
if ($version.build_id -ne 'LANTERNLINE_R7_WEB_MVP' -or $version.revision -ne 'R7') {
    throw "Refusing to package a non-R7 Web build: $($version.build_id) / $($version.revision)"
}
$manifest = Get-Content -LiteralPath (Join-Path $source 'index.manifest.json') -Raw | ConvertFrom-Json
if ($manifest.orientation -ne 'any') { throw "Refusing to package a single-orientation PWA: $($manifest.orientation)" }

$pckPath = Join-Path $source 'index.pck'
$actualPckHash = (Get-FileHash -LiteralPath $pckPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($version.pck_sha256 -ne $actualPckHash) {
    throw "VERSION.json PCK hash mismatch: $($version.pck_sha256) != $actualPckHash"
}

$wasmPath = Join-Path $source 'index.wasm'
$wasmStream = [IO.File]::OpenRead($wasmPath)
try {
    $wasmMagic = @($wasmStream.ReadByte(), $wasmStream.ReadByte(), $wasmStream.ReadByte(), $wasmStream.ReadByte())
} finally {
    $wasmStream.Dispose()
}
if (($wasmMagic[0] -eq 0x00 -and $wasmMagic[1] -eq 0x61 -and $wasmMagic[2] -eq 0x73 -and $wasmMagic[3] -eq 0x6d)) {
    Write-Host 'Web WASM delivery: standard raw Godot WebAssembly'
} elseif (($wasmMagic[0] -eq 0x1f -and $wasmMagic[1] -eq 0x8b)) {
    Write-Host 'Web WASM delivery: deterministic gzip limited-host variant'
} else {
    throw 'R7 Web WASM must be standard raw WebAssembly or the verified deterministic gzip payload.'
}

$html = Get-Content -LiteralPath (Join-Path $source 'index.html') -Raw
foreach ($runtimeName in @('index.pck', 'index.wasm')) {
    $sizeMatch = [regex]::Match($html, '"' + [regex]::Escape($runtimeName) + '":(\d+)')
    if (-not $sizeMatch.Success) { throw "HTML runtime size missing: $runtimeName" }
    $actualSize = (Get-Item -LiteralPath (Join-Path $source $runtimeName)).Length
    if ([int64]$sizeMatch.Groups[1].Value -ne $actualSize) {
        throw "HTML runtime size mismatch for $runtimeName"
    }
}

$cacheInputNames = @('index.pck', 'index.wasm', 'index.js', 'index.html')
$cacheInputHashes = foreach ($name in $cacheInputNames) {
    (Get-FileHash -LiteralPath (Join-Path $source $name) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$cacheBytes = [Text.Encoding]::UTF8.GetBytes(($cacheInputHashes -join '|'))
$cacheHasher = [Security.Cryptography.SHA256]::Create()
try {
    $cacheHash = (($cacheHasher.ComputeHash($cacheBytes) | ForEach-Object { $_.ToString('x2') }) -join '')
} finally {
    $cacheHasher.Dispose()
}
$expectedCacheVersion = "r7_$($cacheHash.Substring(0, 16))"
$worker = Get-Content -LiteralPath (Join-Path $source 'index.service.worker.js') -Raw
$cacheMatch = [regex]::Match($worker, "const CACHE_VERSION = '([^']+)';")
if (-not $cacheMatch.Success -or $cacheMatch.Groups[1].Value -ne $expectedCacheVersion) {
    throw "Service-worker cache mismatch: $($cacheMatch.Groups[1].Value) != $expectedCacheVersion"
}

$publicLeakPattern = '(?i)(?<![A-Za-z0-9_])[A-Za-z]:[\\/]|source_blends?|render_command|blender_sources|\.blend\b'
$publicTextFiles = @(
    $actualFiles |
        Where-Object { $_.Extension -in @('.html', '.js', '.json', '.md') } |
        Select-Object -ExpandProperty FullName
)
$publicTextLeaks = @(Select-String -LiteralPath $publicTextFiles -Pattern $publicLeakPattern)
if ($publicTextLeaks.Count -gt 0) {
    $locations = ($publicTextLeaks | ForEach-Object { "$($_.Path):$($_.LineNumber)" }) -join ', '
    throw "Public Web companion files leak authoring lineage: $locations"
}
$pckUtf8 = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($pckPath))
$pckLeakPattern = '(?i)source_blends?|render_command|blender_sources|[A-Za-z]:[\\/]{1,2}(?:Users|Program Files)|D:[\\/]{1,2}AI 종합 폴더'
$pckLeak = [regex]::Match($pckUtf8, $pckLeakPattern)
if ($pckLeak.Success) {
    throw "Exported PCK leaks authoring lineage token: $($pckLeak.Value)"
}

$packageMembers = @($required | ForEach-Object { Join-Path $source $_ })
Compress-Archive -LiteralPath $packageMembers -DestinationPath $target -Force
$zip = Get-Item -LiteralPath $target
$hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
Write-Host "HTML package: $target"
Write-Host "HTML_PACKAGE_BYTES=$($zip.Length)"
Write-Host "HTML_PACKAGE_SHA256=$hash"
