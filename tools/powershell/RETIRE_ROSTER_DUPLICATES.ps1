param([string]$ReportDirectory = 'reports/existing_roster_spritegen_20260911')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$prefix = $projectRoot.TrimEnd('\') + '\'
$reportPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $ReportDirectory))
if (-not $reportPath.StartsWith((Join-Path $projectRoot 'reports') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Retirement report must stay under project reports.' }
$manifest = Get-Content -LiteralPath (Join-Path $reportPath 'retirement_manifest.json') -Raw | ConvertFrom-Json
if ($manifest.status -ne 'VERIFIED_REPLACEMENT_READY_FOR_REDUNDANT_OUTPUT_RETIREMENT') { throw 'Replacement verification is missing.' }
$retainedBuild = Join-Path $projectRoot ('builds\' + $manifest.retained_build)
$health = Invoke-RestMethod -Uri 'http://127.0.0.1:8770/__local_game_status'
if ($health.build -ne ('builds/' + $manifest.retained_build)) { throw 'The verified replacement is not the active player.' }
$roots = @($manifest.roots | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $projectRoot $_)) })
$protectedExtensions = @('.wav','.ogg','.oga','.mp3','.flac','.m4a','.aac','.opus','.mid','.midi','.mp4','.webm','.ogv','.avi','.mov','.mkv')
foreach ($targetRoot in $roots) {
    if (-not $targetRoot.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $targetRoot -eq $retainedBuild) { throw "Unsafe cleanup root: $targetRoot" }
    if (Test-Path -LiteralPath $targetRoot) {
        $item = Get-Item -LiteralPath $targetRoot -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked cleanup root: $targetRoot" }
    }
}
$verified = [Collections.Generic.List[string]]::new()
foreach ($row in $manifest.files) {
    $target = [IO.Path]::GetFullPath((Join-Path $projectRoot $row.path))
    $inSelectedRoot = @($roots | Where-Object { $target.StartsWith($_.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not $inSelectedRoot -or $target.StartsWith($retainedBuild + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe retirement file: $target" }
    if ([IO.Path]::GetExtension($target).ToLowerInvariant() -in $protectedExtensions) { throw "Media retirement prohibited: $target" }
    $item = Get-Item -LiteralPath $target -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked retirement file: $target" }
    if ($item.Length -ne $row.bytes -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $row.sha256) { throw "Retirement hash mismatch: $target" }
    $verified.Add($target)
}
Write-Output "RETIREMENT_HASHES_VERIFIED $($verified.Count) files"
$removed = 0
foreach ($target in $verified) {
    Remove-Item -LiteralPath $target -Force
    $removed++
    if ($removed % 3000 -eq 0) { Write-Output "RETIRED $removed files" }
}
# Only empty project directories are removed. Protected media and links survive.
foreach ($targetRoot in $roots) {
    if (-not (Test-Path -LiteralPath $targetRoot)) { continue }
    $directories = @(Get-ChildItem -LiteralPath $targetRoot -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending)
    $directories += Get-Item -LiteralPath $targetRoot -Force
    foreach ($directory in $directories) {
        $resolved = [IO.Path]::GetFullPath($directory.FullName)
        if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe directory: $resolved" }
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if (@(Get-ChildItem -LiteralPath $resolved -Force).Count -eq 0) { Remove-Item -LiteralPath $resolved -Force }
    }
}
@{status='COMPLETE';removed_files=$removed;removed_bytes=$manifest.retirement_bytes;retained_media=$manifest.protected_media_retained;retained_build=$manifest.retained_build} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportPath 'retirement_result.json') -Encoding utf8
Write-Output "RETIREMENT_COMPLETE files=$removed bytes=$($manifest.retirement_bytes)"
