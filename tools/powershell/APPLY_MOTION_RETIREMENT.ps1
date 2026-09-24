. "$PSScriptRoot\COMMON.ps1"
$root = [IO.Path]::GetFullPath((Get-ProjectRoot))
$rootPrefix = $root.TrimEnd('\') + '\'
$report = Join-Path $root 'reports/combat_motion_20260913'
$plan = Get-Content -LiteralPath (Join-Path $report 'retirement_manifest.json') -Raw | ConvertFrom-Json
if ($plan.status -ne 'VERIFIED_REPLACEMENT_READY_FOR_REDUNDANT_OUTPUT_RETIREMENT') { throw 'Unverified retirement plan' }
if (Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Where-Object { $_.CommandLine -like '*SD_STORY_RPG_GODOT*' -or $_.CommandLine -like '*--path godot*' }) { throw 'Godot is still using project caches' }
$keep = [IO.Path]::GetFullPath((Join-Path $root $plan.retained_build))
$protected = '\.(wav|ogg|oga|mp3|flac|m4a|aac|opus|mid|midi|mp4|webm|ogv|avi|mov|mkv)$'
# Verify every absolute target and hash before deleting any of them.
$targets = foreach ($file in $plan.files) {
    $target = [IO.Path]::GetFullPath((Join-Path $root $file.path))
    if (-not $target.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase) -or $target.StartsWith($keep+'\',[StringComparison]::OrdinalIgnoreCase) -or $target -match $protected) { throw "Protected path: $target" }
    $allowed = $false
    foreach ($rel in $plan.roots) {
        $allowedRoot = [IO.Path]::GetFullPath((Join-Path $root $rel)).TrimEnd('\')+'\'
        if ($target.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)) { $allowed = $true }
    }
    if (-not $allowed) { throw "Unlisted retirement root: $target" }
    if ((Get-FileSha256 $target) -ne $file.sha256) { throw "Changed retirement file: $target" }
    $target
}
foreach ($target in $targets) { Remove-Item -LiteralPath $target -Force }
# Remove only empty directories, bottom-up, inside the verified redundant roots.
foreach ($rel in $plan.roots) {
    if ($rel.StartsWith('reports/')) { continue }
    $directory = [IO.Path]::GetFullPath((Join-Path $root $rel))
    if (-not $directory.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase) -or $directory -eq $keep) { throw 'Invalid directory cleanup target' }
    if (-not (Test-Path -LiteralPath $directory)) { continue }
    Get-ChildItem -LiteralPath $directory -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
        if (@(Get-ChildItem -LiteralPath $_.FullName -Force).Count -eq 0) { Remove-Item -LiteralPath $_.FullName -Force }
    }
    if (@(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) { Remove-Item -LiteralPath $directory -Force }
}
$version = Get-Content -LiteralPath (Join-Path $keep 'VERSION.json') -Raw | ConvertFrom-Json
if ((Get-FileSha256 (Join-Path $keep ($version.runtime_artifact_base+'.pck'))) -ne $plan.pck_sha256) { throw 'Retained build changed' }
@{status='COMPLETED';files_removed=$targets.Count;bytes_removed=$plan.retirement_bytes;retained_build=$plan.retained_build;pck_sha256=$plan.pck_sha256;music_and_intro_preserved=$true} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $report 'retirement_result.json') -Encoding utf8
Write-Host "Retired $($targets.Count) redundant files; preserved current build and all media."
