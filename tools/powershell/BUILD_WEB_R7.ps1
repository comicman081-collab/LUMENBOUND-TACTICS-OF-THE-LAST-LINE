param(
    [string]$Tag = 'r7_current',
    [string]$MapRevision = 'R7',
    [switch]$ReplaceExisting
)
. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
Copy-GodotWebTemplatesToProjectProfile $root
$runtimeCombatBuilder = Join-Path $root 'tools\web\build_runtime_combat_packs.py'
if (-not (Test-Path -LiteralPath $runtimeCombatBuilder -PathType Leaf)) { throw "Runtime combat pack builder missing: $runtimeCombatBuilder" }
Invoke-Checked 'python' @($runtimeCombatBuilder)

if ($Tag -notmatch '^[a-z0-9_]+$') { throw "Invalid Web build tag: $Tag" }
$development = Join-Path $root "builds\web_${Tag}_development"
$release = Join-Path $root "builds\web_${Tag}_release"
$buildRoot = [IO.Path]::GetFullPath((Join-Path $root 'builds'))

function Assert-ReplaceableWebOutput([string]$Directory) {
    $resolved = [IO.Path]::GetFullPath($Directory)
    $prefix = $buildRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace a path outside builds/: $resolved"
    }
    $leaf = Split-Path -Leaf $resolved
    if ($leaf -notmatch '^web_[a-z0-9_]+_(development|release)$') {
        throw "Refusing to replace a non-Web output directory: $resolved"
    }
}

function ConvertTo-HashedR7RuntimeArtifacts([string]$Directory) {
    # A stable R7 output directory must still be able to replace an already
    # service-worker-cached PCK during local Web QA.  The content hash changes
    # the runtime artifact name only; it never creates another R build name.
    $pckPath = Join-Path $Directory 'index.pck'
    $wasmPath = Join-Path $Directory 'index.wasm'
    $pckHash = (Get-FileHash -LiteralPath $pckPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $artifactBase = "r7_current_$($pckHash.Substring(0, 12))"
    $pckName = "$artifactBase.pck"
    $wasmName = "$artifactBase.wasm"
    $pckTarget = Join-Path $Directory $pckName
    $wasmTarget = Join-Path $Directory $wasmName
    if (Test-Path -LiteralPath $pckTarget) { throw "Unexpected existing hashed PCK in fresh R7 output: $pckTarget" }
    if (Test-Path -LiteralPath $wasmTarget) { throw "Unexpected existing hashed WASM in fresh R7 output: $wasmTarget" }

    Move-Item -LiteralPath $pckPath -Destination $pckTarget
    Move-Item -LiteralPath $wasmPath -Destination $wasmTarget

    $htmlPath = Join-Path $Directory 'index.html'
    $html = Get-Content -LiteralPath $htmlPath -Raw
    $htmlOld = '"executable":"index"'
    $htmlNew = '"executable":"' + $artifactBase + '"'
    $html = $html.Replace($htmlOld, $htmlNew)
    $html = $html -replace '"index\.pck":\d+', ('"' + $pckName + '":' + (Get-Item -LiteralPath $pckTarget).Length)
    $html = $html -replace '"index\.wasm":\d+', ('"' + $wasmName + '":' + (Get-Item -LiteralPath $wasmTarget).Length)
    # Godot 4.7.1 web templates can emit either the legacy `Engine` global or
    # the current `Godot` global depending on the installed export template.
    # Resolve the supported global explicitly so a valid release never reaches
    # the bootstrap with an undefined constructor.
    $engineBootstrap = "const GameEngine = typeof Engine !== 'undefined' ? Engine : Godot;"
    if ($html -notmatch [regex]::Escape($engineBootstrap)) {
        $html = $html.Replace('const engine = new Engine(GODOT_CONFIG);', "$engineBootstrap`nconst engine = new GameEngine(GODOT_CONFIG);")
    }
    if ($html.IndexOf($htmlNew, [StringComparison]::Ordinal) -lt 0) { throw 'Failed to set hashed R7 executable in Web HTML.' }
    if ($html -notmatch [regex]::Escape($engineBootstrap)) { throw 'Failed to add the compatible Godot Web bootstrap.' }
    $html = $html.Replace('const missing = Engine.getMissingFeatures({', 'const missing = GameEngine.getMissingFeatures({')
    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

    $workerPath = Join-Path $Directory 'index.service.worker.js'
    $worker = Get-Content -LiteralPath $workerPath -Raw
    $workerOld = '"index.wasm","index.pck"'
    $workerNew = '"' + $wasmName + '","' + $pckName + '"'
    $worker = $worker.Replace($workerOld, $workerNew)
    if ($worker -notmatch [regex]::Escape("`"$pckName`"")) { throw 'Failed to set hashed R7 PCK in service worker cache list.' }
    # The generated cache version is tied to the export-template timestamp,
    # not to our PCK.  Pin it to the immutable runtime artifact so a rebuilt
    # fixed R7 directory cannot serve a stale index.js / PCK pair.
    $cacheVersionPattern = "const CACHE_VERSION = '[^']+';"
    $cacheVersionReplacement = "const CACHE_VERSION = '$artifactBase';"
    $worker = [regex]::Replace($worker, $cacheVersionPattern, $cacheVersionReplacement, 1)
    if ($worker -notmatch [regex]::Escape($cacheVersionReplacement)) { throw 'Failed to version the R7 service worker cache.' }
    Set-Content -LiteralPath $workerPath -Value $worker -Encoding UTF8

    return [ordered]@{
        base = $artifactBase
        pck_name = $pckName
        wasm_name = $wasmName
        pck_sha256 = $pckHash
    }
}

foreach ($directory in @($development, $release)) {
    if (Test-Path -LiteralPath $directory -PathType Container) {
        $existing = @(Get-ChildItem -LiteralPath $directory -Force)
        if ($existing.Count -gt 0) {
            if (-not $ReplaceExisting) { throw "Refusing to overwrite non-empty Web build directory without -ReplaceExisting: $directory" }
            Assert-ReplaceableWebOutput $directory
            Remove-Item -LiteralPath $directory -Recurse -Force
        }
    }
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), '--export-debug', 'Web Development', (Join-Path $development 'index.html'))
Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), '--export-release', 'Web HTML Release', (Join-Path $release 'index.html'))
$runtimeArtifacts = ConvertTo-HashedR7RuntimeArtifacts $release
$compressor = Join-Path $root 'tools\web\compress_web_wasm.py'
if (-not (Test-Path -LiteralPath $compressor -PathType Leaf)) { throw "Web WASM compressor missing: $compressor" }
$pako = Join-Path $root 'tools\web\pako_inflate.min.js'
if (-not (Test-Path -LiteralPath $pako -PathType Leaf)) { throw "Web gzip fallback missing: $pako" }
Copy-Item -LiteralPath $pako -Destination (Join-Path $release 'pako_inflate.min.js') -Force
Invoke-Checked 'python' @($compressor, $release)

@'
# LANTERNLINE R7 SRPG Chapter Map Web Review

Serve through a local HTTP server. This is a Godot 4.7.1 Compatibility Web export.
The SRPG-style hex layer is chapter traversal only; combat remains the existing
30 Hz deterministic real-time SD battle. Production approval remains pending
user review. Runtime audio is sourced only from the local Sound folder; no
external audio service is used.
'@ | Set-Content -LiteralPath (Join-Path $release 'README_HTML.md') -Encoding UTF8

[ordered]@{
    build_id = "LANTERNLINE_$($Tag.ToUpperInvariant())_WEB"
    engine = 'Godot 4.7.1-stable'
    renderer = 'Compatibility'
    target = 'Web HTML Release'
    feature = 'SRPG chapter traversal map'
    map_revision = $MapRevision
    runtime_artifact_base = $runtimeArtifacts.base
    pck_sha256 = $runtimeArtifacts.pck_sha256
    battle_contract = 'existing deterministic real-time SD battle preserved'
    production_approved = $false
    created_utc = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $release 'VERSION.json') -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $root 'docs\LICENSE_POLICY.md') -Destination (Join-Path $release 'LICENSES.md')

$required = @('index.html','index.js',$runtimeArtifacts.wasm_name,$runtimeArtifacts.pck_name,'index.png','index.manifest.json','index.service.worker.js','index.offline.html','README_HTML.md','VERSION.json','LICENSES.md')
foreach ($name in $required) {
    $path = Join-Path $release $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required R7 Web file missing: $path" }
    if ((Get-Item -LiteralPath $path).Length -le 0) { throw "Required R7 Web file empty: $path" }
}
Write-Host "WEB_R7_DEVELOPMENT=$development"
Write-Host "WEB_R7_RELEASE=$release"
