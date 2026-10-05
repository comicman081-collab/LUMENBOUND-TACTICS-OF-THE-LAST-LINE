param([string]$Plan = 'reports/startup_r24_20261005/storage_retirement_plan.json')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\COMMON.ps1"
$root = [IO.Path]::GetFullPath((Get-ProjectRoot))
$rootPrefix = $root.TrimEnd('\') + '\'
$planPath = [IO.Path]::GetFullPath((Join-Path $root $Plan))
if (-not $planPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Plan outside project' }
$record = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
if ($record.status -ne 'HASHED_READY_AFTER_REPLACEMENT_PASS' -or $record.gate.startup_under_10s_repetitions -ne 3 -or $record.gate.fps_scored_cases -ne 11 -or $record.gate.runtime_checks -ne 30 -or -not $record.gate.full_intro_pass -or -not $record.gate.settled_visual_review_pass -or $record.gate.bosses_source_density_pass -ne 23) { throw 'Replacement gates incomplete' }
$kept = (Resolve-Path -LiteralPath $record.candidate_pck).ProviderPath
if (-not $kept.StartsWith((Join-Path $rootPrefix 'builds\web_visual_r24_release\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected kept build' }
if ((Get-FileHash -LiteralPath $kept -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.candidate_pck_sha256) { throw 'Replacement differs from verification' }
$manifest = (Resolve-Path -LiteralPath $record.file_hash_manifest).ProviderPath
if (-not $manifest.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Missing project retirement manifest' }

# Resolve and validate every bounded directory before the first deletion.
$targets = @()
foreach ($target in $record.targets) {
 $absolute = (Resolve-Path -LiteralPath $target).ProviderPath
 if ([IO.Path]::GetFullPath($target) -ne $absolute -or -not $absolute.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Target boundary: $target" }
 $relative = $absolute.Substring($rootPrefix.Length)
 $permitted = $relative -match '^builds\\web_visual_r24_[a-z_]*fps_probe$' -or $relative -eq 'builds\web_visual_r23_release' -or $relative -match '^work\\build_output_quarantine\\web_visual_r24_release_[a-f0-9]{32}$' -or $relative -match '^godot\\\.runtime_profile\\runs\\\d+-\d{13}$'
 if (-not $permitted) { throw "Unexpected target: $relative" }
 $item = Get-Item -LiteralPath $absolute -Force
 if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Nonordinary directory: $absolute" }
 if (@(Get-ChildItem -LiteralPath $absolute -Recurse -Force -Attributes ReparsePoint).Count -ne 0) { throw "Reparse point below $absolute" }
 $targets += $absolute
}
$health = Invoke-RestMethod 'http://127.0.0.1:8780/__local_game_status'
if ($health.service -ne 'lumenbound-local-player-v2' -or $health.build -ne 'builds/web_visual_r24_release') { throw 'User preview must serve the verified replacement first' }
foreach ($port in @(8782,8783)) {
 if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) { throw "Probe server still active: $port" }
}
$protected = @()
foreach ($name in @('web_visual_r21_release','web_visual_r22_release')) {
 $pack = @(Get-ChildItem -LiteralPath (Join-Path $root "builds\$name") -Filter '*.pck' -File)
 if ($pack.Count -ne 1) { throw 'Ambiguous protected production build' }
 $protected += [ordered]@{path=$pack[0].FullName;sha256=(Get-FileHash -LiteralPath $pack[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$freeBefore = (Get-PSDrive -Name D).Free
$removed = @()
foreach ($target in $targets) {
 Remove-Item -LiteralPath $target -Recurse -Force
 if (Test-Path -LiteralPath $target) { throw "Incomplete retirement: $target" }
 $removed += $target
}
if ((Get-FileHash -LiteralPath $kept -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.candidate_pck_sha256) { throw 'Kept build changed during cleanup' }
foreach ($entry in $protected) {
 if ((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) { throw 'Protected deployment build changed' }
}
$result = [ordered]@{status='DISPOSED_VERIFIED';time_utc=[DateTime]::UtcNow.ToString('o');targets=$removed;file_count=$record.file_count;logical_bytes=$record.logical_bytes;estimated_physical_reclaim_bytes=$record.estimated_reclaim_bytes;media_duplicates_with_verified_kept_copy=$record.media_duplicates_with_verified_kept_copy;file_hash_manifest=$manifest;kept_pck=$kept;kept_pck_sha256=$record.candidate_pck_sha256;drive_free_before=$freeBefore;drive_free_after=(Get-PSDrive -Name D).Free;protected_production_builds=$protected;production_deployments_modified=$false}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path (Split-Path -Parent $planPath) 'storage_retirement_result.json') -Encoding UTF8
$record.status = 'DISPOSED_VERIFIED'
$record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $planPath -Encoding UTF8
'RETIRED_DIRECTORY_COUNT=' + $removed.Count
'ESTIMATED_PHYSICAL_RECLAIM_BYTES=' + $record.estimated_reclaim_bytes
