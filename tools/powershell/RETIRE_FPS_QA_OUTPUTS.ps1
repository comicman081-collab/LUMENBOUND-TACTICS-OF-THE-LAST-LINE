param([string]$Plan = 'reports/performance_r23_20261004/storage_retirement_plan.json')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\COMMON.ps1"
$root = [IO.Path]::GetFullPath((Get-ProjectRoot))
$rootPrefix = $root.TrimEnd('\') + '\'
$planPath = [IO.Path]::GetFullPath((Join-Path $root $Plan))
if (-not $planPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Plan is outside the project' }
$record = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
if ($record.status -ne 'HASHED_READY_AFTER_REPLACEMENT_PASS' -or $record.gate.fps_repetitions_pass -ne 2 -or $record.gate.scored_cases_each -ne 11 -or -not $record.gate.wave_web_flow_checks_pass) { throw 'Replacement gates are not complete' }
$kept = (Resolve-Path -LiteralPath $record.candidate_pck).ProviderPath
if ((Get-FileHash -LiteralPath $kept -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.candidate_pck_sha256) { throw 'Kept build differs from verified replacement' }
if (-not (Test-Path -LiteralPath $record.file_hash_manifest -PathType Leaf)) { throw 'Pre-disposal path/hash manifest missing' }

# Resolve every absolute target and check all boundaries before any mutation.
# Each permitted target is an owned probe, recorded old R23 output, or isolated
# QA profile. Never invoke another shell for moving/deleting these paths.
$targets = @()
foreach ($target in $record.targets) {
 $absolute = (Resolve-Path -LiteralPath $target).ProviderPath
 if ([IO.Path]::GetFullPath($target) -ne $absolute -or -not $absolute.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Unresolved target boundary: $target" }
 $relative = $absolute.Substring($rootPrefix.Length)
 $permitted = $relative -match '^builds\\web_visual_r(?:22|23)_[a-z_]*fps_probe$' -or $relative -match '^work\\build_output_quarantine\\web_visual_r23_release_[a-f0-9]{32}$' -or $relative -match '^godot\\\.runtime_profile\\runs\\\d+-\d{13}$'
 if (-not $permitted) { throw "Unexpected retirement target: $relative" }
 $item = Get-Item -LiteralPath $absolute -Force
 if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Nonordinary directory: $absolute" }
 $links = @(Get-ChildItem -LiteralPath $absolute -Recurse -Force -Attributes ReparsePoint)
 if ($links.Count -ne 0) { throw "Reparse point below target: $absolute" }
 $targets += $absolute
}
$health = Invoke-RestMethod 'http://127.0.0.1:8780/__local_game_status'
if ($health.service -ne 'lumenbound-local-player-v2' -or $health.build -ne 'builds/web_visual_r23_release') { throw 'Local release server is not attached to the kept candidate' }
$freeBefore = (Get-PSDrive -Name D).Free
$removed = @()
foreach ($target in $targets) {
 Remove-Item -LiteralPath $target -Recurse -Force
 if (Test-Path -LiteralPath $target) { throw "Retirement incomplete: $target" }
 $removed += $target
}
if ((Get-FileHash -LiteralPath $kept -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.candidate_pck_sha256) { throw 'Kept build changed during retirement' }
$result = [ordered]@{status='DISPOSED_VERIFIED';time_utc=[DateTime]::UtcNow.ToString('o');targets=$removed;file_count=$record.file_count;logical_bytes=$record.logical_bytes;estimated_physical_reclaim_bytes=$record.estimated_reclaim_bytes;media_duplicates_with_verified_kept_copy=$record.media_duplicates_with_verified_kept_copy;file_hash_manifest=$record.file_hash_manifest;kept_pck=$kept;kept_pck_sha256=$record.candidate_pck_sha256;drive_free_before=$freeBefore;drive_free_after=(Get-PSDrive -Name D).Free;production_deployments_modified=$false}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path (Split-Path -Parent $planPath) 'storage_retirement_result.json') -Encoding UTF8
$record.status = 'DISPOSED_VERIFIED'
$record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $planPath -Encoding UTF8
'RETIRED_DIRECTORY_COUNT=' + $removed.Count
'ESTIMATED_PHYSICAL_RECLAIM_BYTES=' + $record.estimated_reclaim_bytes
