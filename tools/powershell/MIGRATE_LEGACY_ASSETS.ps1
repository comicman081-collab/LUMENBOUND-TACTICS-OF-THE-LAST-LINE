Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

throw 'DEPRECATED: the canonical bridge path is now godot/assets/generated_import. This historical migration must not run.'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$assetsRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'godot\assets'))
$sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $assetsRoot 'generated_import'))
$targetRoot = [System.IO.Path]::GetFullPath((Join-Path $assetsRoot 'placeholders_legacy'))
$reportRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'reports\art_pipeline'))

foreach ($path in @($sourceRoot, $targetRoot, $reportRoot)) {
    if (-not $path.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved path escaped project root: $path"
    }
}
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    Write-Host 'Legacy source already moved; nothing to do.'
    exit 0
}

$sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force)
if ($sourceFiles.Count -lt 93) {
    throw "Expected at least 93 legacy files before migration, found $($sourceFiles.Count)."
}

New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null

$baseline = foreach ($file in $sourceFiles) {
    [ordered]@{
        relative_path = $file.FullName.Substring($sourceRoot.Length + 1).Replace('\', '/')
        bytes = $file.Length
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        classification = if ($file.Extension -in @('.png', '.json')) { 'DEV_PLACEHOLDER' } else { 'LEGACY_METADATA' }
    }
}
$baselineObject = [ordered]@{
    schema_version = 1
    captured_utc = [DateTime]::UtcNow.ToString('o')
    source = 'res://assets/generated_import'
    destination = 'res://assets/placeholders_legacy'
    file_count = $sourceFiles.Count
    files = $baseline
}
$baselineJson = $baselineObject | ConvertTo-Json -Depth 6
$baselinePath = Join-Path $reportRoot 'LEGACY_ASSET_BASELINE.json'
[System.IO.File]::WriteAllText($baselinePath, $baselineJson + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

foreach ($item in Get-ChildItem -LiteralPath $sourceRoot -Force) {
    $destination = Join-Path $targetRoot $item.Name
    if (Test-Path -LiteralPath $destination) {
        throw "Migration target already exists: $destination"
    }
    Move-Item -LiteralPath $item.FullName -Destination $destination
}

$manifestPath = Join-Path $targetRoot 'import_manifest.json'
if (Test-Path -LiteralPath $manifestPath) {
    $manifestText = [System.IO.File]::ReadAllText($manifestPath)
    $manifestText = $manifestText.Replace('res://assets/generated_import/', 'res://assets/placeholders_legacy/')
    [System.IO.File]::WriteAllText($manifestPath, $manifestText, [System.Text.UTF8Encoding]::new($false))
}

$remaining = @(Get-ChildItem -LiteralPath $sourceRoot -Force)
if ($remaining.Count -ne 0) {
    throw "Legacy source is not empty after migration: $($remaining.Count) entries"
}
Remove-Item -LiteralPath $sourceRoot

$movedFiles = @(Get-ChildItem -LiteralPath $targetRoot -Recurse -File -Force)
foreach ($row in $baseline) {
    $moved = Join-Path $targetRoot $row.relative_path.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $moved -PathType Leaf)) { throw "Missing moved file: $moved" }
    # This metadata file is intentionally rewritten to point at the legacy
    # runtime root. PNG and atlas payloads remain byte-identical.
    if ($row.relative_path -eq 'import_manifest.json') { continue }
    $hash = (Get-FileHash -LiteralPath $moved -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $row.sha256) { throw "SHA-256 changed during move: $moved" }
}

Write-Host "Moved $($movedFiles.Count) legacy files to $targetRoot; old directory removed; SHA-256 preserved."
