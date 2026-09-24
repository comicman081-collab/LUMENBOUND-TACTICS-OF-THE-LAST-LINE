$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$report=Join-Path $root 'reports/storage_cleanup_20260911'
if (Test-Path -LiteralPath (Join-Path $report 'additional_cleanup_complete.json')) { Write-Output 'This recorded additional cleanup has already completed.'; return }
$prefix=$root+'\'
$records=[System.Collections.Generic.List[object]]::new()
function Assert-LocalPath([string]$path) {
    $resolved=(Resolve-Path -LiteralPath $path).Path
    if (-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Outside project: $resolved" }
    $item=Get-Item -LiteralPath $resolved -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse input' }
    return $resolved
}
function Remove-RecordedFile([string]$path,[string]$hash,[string]$reason,[string]$retained) {
    $path=Assert-LocalPath $path
    if ([IO.Path]::GetExtension($path).ToLowerInvariant() -in @('.wav','.ogg','.mp3','.flac','.m4a','.aac','.mp4','.ogv','.webm','.mov')) { throw "Protected media extension: $path" }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $hash) { throw "File changed: $path" }
    $row=@{path=$path;sha256=$hash;bytes=(Get-Item -LiteralPath $path).Length;reason=$reason;retained=$retained}
    $records.Add($row)
    $row | ConvertTo-Json -Depth 4 -Compress | Add-Content -LiteralPath (Join-Path $report 'additional_retired_files.jsonl') -Encoding utf8
    Remove-Item -LiteralPath $path -Force
}

# Complete all archive preflights before removing any loose copy.
foreach ($kind in @('art','lfs')) {
    $archive=Get-Content -LiteralPath (Join-Path $report ($kind+'_archive.json')) -Raw | ConvertFrom-Json
    $archivePath=Assert-LocalPath $archive.archive
    if ($archive.status -ne 'LOSSLESS_ARCHIVE_VERIFIED' -or (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $archive.archive_sha256) { throw 'Archive was not verified' }
}
$compressed=Get-Content -LiteralPath (Join-Path $report 'compressed_reports.json') -Raw | ConvertFrom-Json
foreach ($row in $compressed) {
    if (-not (Test-Path -LiteralPath $row.gzip)) { throw 'Compressed report missing' }
    if (Test-Path -LiteralPath $row.source) { Remove-RecordedFile $row.source $row.sha256 'losslessly compressed diagnostic data' $row.gzip }
}

# Only obsolete QA copies are eligible; current storage verification, source
# artwork and the remaining sound collection are outside this allowlist.
$groups=Get-Content -LiteralPath (Join-Path $report 'duplicate_images.json') -Raw | ConvertFrom-Json
foreach ($group in $groups) {
    $available=@($group.paths | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path -LiteralPath $_ })
    $eligible=@($available | Where-Object { $_ -match '\\reports\\(gameplay_qa|title_prologue_qa|player_feedback_20260911)\\' })
    if ($available.Count -le 1 -or $eligible.Count -eq 0) { continue }
    $canonical=@($available | Where-Object { $_ -notin $eligible } | Select-Object -First 1)
    if ($canonical.Count -eq 0) { $canonical=@($eligible | Sort-Object { (Get-Item -LiteralPath $_).LastWriteTime } -Descending | Select-Object -First 1) }
    if ((Get-FileHash -LiteralPath $canonical[0] -Algorithm SHA256).Hash -ne $group.sha256) { throw 'Canonical screenshot changed' }
    foreach ($path in $eligible) {
        if ($path -ne $canonical[0]) { Remove-RecordedFile $path $group.sha256 'identical obsolete QA screenshot' $canonical[0] }
    }
}

foreach ($kind in @('art','lfs')) {
    $archive=Get-Content -LiteralPath (Join-Path $report ($kind+'_archive.json')) -Raw | ConvertFrom-Json
    if ($archive.status -ne 'LOSSLESS_ARCHIVE_VERIFIED' -or (Get-FileHash -LiteralPath $archive.archive -Algorithm SHA256).Hash -ne $archive.archive_sha256) { throw 'Archive was not verified' }
    foreach ($row in $archive.members) {
        Remove-RecordedFile $row.path $row.sha256 'loose copy consolidated into verified recovery archive' ($archive.archive+'::'+$row.member)
    }
    foreach ($path in $archive.root_directories) {
        $path=Assert-LocalPath $path
        if (@(Get-ChildItem -LiteralPath $path -Force -Recurse -File).Count -ne 0) { throw 'Unexpected file remains in retired source directory' }
        if (@(Get-ChildItem -LiteralPath $path -Force -Recurse -Attributes ReparsePoint).Count -ne 0) { throw 'Reparse descendant' }
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

$dist=Join-Path $root 'dist/client'
if (Test-Path -LiteralPath $dist) {
    $dist=Assert-LocalPath $dist
    if (@(Get-ChildItem -LiteralPath $dist -Force -Recurse -Attributes ReparsePoint).Count) { throw 'Reparse dist' }
    foreach ($file in @(Get-ChildItem -LiteralPath $dist -Force -Recurse -File)) {
        Remove-RecordedFile $file.FullName (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash 'obsolete local deployment staging copy' 'builds/web_verified_local_20260911_release'
    }
    Remove-Item -LiteralPath $dist -Recurse -Force
}
$records | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $report 'additional_retired_files.json') -Encoding utf8
Write-Output ("ADDITIONAL_LOOSE_COPIES_REMOVED {0:N3} GiB" -f (($records | Measure-Object -Property bytes -Sum).Sum/1GB))
