Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$quarantineRoot = Join-Path $taskRoot 'work/gameplay_qa_quarantine_20260907/enclosed_white_matte/retained_failures'
if (Test-Path -LiteralPath $quarantineRoot) { throw 'Immutable quarantine already exists.' }
$targets = @(
    @{source='work/enclosed_matte_repair/r1/CHR004'; name='CHR004_incomplete_hole_mask'; reason='The fifth enclosed hair crescent remained opaque.'},
    @{source='godot/assets/runtime_web/full_density/r1'; name='full_density_r1'; reason='CHR002 and CHR004 enclosed matte; entire failed batch retained.'},
    @{source='work/full_density/r1'; name='full_density_r1_sources_and_evidence'; reason='Retain source derivatives, green masters, QA, hashes and provenance together.'},
    @{source='godot/assets/runtime_web/combat_signature/r13'; name='signature_r13'; reason='User-confirmed enclosed matte in hair and arm.'},
    @{source='godot/assets/runtime_web/combat_signature/r14'; name='signature_r14'; reason='Per-frame chroma provenance contract incomplete.'},
    @{source='godot/assets/runtime_web/combat_signature/r15'; name='signature_r15'; reason='Partial build rejected by thin-hair fringe gate.'},
    @{source='godot/assets/generated_import/chroma_key_derivatives/battle_signature_r15'; name='signature_r15_partial_derivatives'; reason='Keep partial rejected green/keyed source branch.'}
)
# Validate every exact absolute source/destination before any recursive move.
$records = @()
foreach ($item in $targets) {
    $resolved = (Resolve-Path -LiteralPath (Join-Path $taskRoot $item.source)).Path
    $destination = [IO.Path]::GetFullPath((Join-Path $quarantineRoot $item.name))
    if (-not $resolved.StartsWith($taskRoot + [IO.Path]::DirectorySeparatorChar) -or -not $destination.StartsWith($quarantineRoot + [IO.Path]::DirectorySeparatorChar)) { throw 'Target escaped project quarantine.' }
    $files = @(Get-ChildItem -LiteralPath $resolved -Recurse -File | ForEach-Object {
        @{relative=[IO.Path]::GetRelativePath($resolved,$_.FullName); sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); bytes=$_.Length}
    })
    $records += @{source=$resolved; destination=$destination; reason=$item.reason; files=$files}
}
New-Item -ItemType Directory -Path $quarantineRoot | Out-Null
$manifest = @{status='QUARANTINE_ONLY_NO_DISPOSAL'; no_deletion=$true; path_remapping_retains_historical_provenance=$true; records=$records}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $quarantineRoot 'retention_manifest.json') -Encoding utf8
foreach ($record in $records) {
    Move-Item -LiteralPath $record.source -Destination $record.destination
    foreach ($file in $record.files) {
        $retained=Join-Path $record.destination $file.relative
        if ((Get-FileHash -LiteralPath $retained -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) { throw "Quarantine hash mismatch: $retained" }
    }
}
Write-Output "QUARANTINE_VERIFIED retained_groups=$($records.Count) deleted=0 root=$quarantineRoot"
