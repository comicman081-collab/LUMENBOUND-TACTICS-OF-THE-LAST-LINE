$ErrorActionPreference='Stop'
$qaRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$qaQuarantine=Join-Path $qaRoot 'work/gameplay_qa_quarantine_20260907/botanical_r18'
$qaTargets=@(
    @{source='godot/assets/art/chapter_map/R18';leaf='runtime_asset'},
    @{source='work/map_art_r18_botanical';leaf='masters'},
    @{source='builds/web_gameplay_qa_20260907_candidate30';leaf='candidate30'},
    @{source='reports/gameplay_qa/20260907_map30_gallery';leaf='map30_gallery'}
)
$qaRows=@()
foreach($qaTarget in $qaTargets){
    $qaSource=(Resolve-Path -LiteralPath (Join-Path $qaRoot $qaTarget.source)).Path
    $qaDestination=[IO.Path]::GetFullPath((Join-Path $qaQuarantine $qaTarget.leaf))
    foreach($qaPath in @($qaSource,$qaDestination)){
        if(-not $qaPath.StartsWith($qaRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Outside project'}
    }
    if(Test-Path -LiteralPath $qaDestination){throw 'Existing destination'}
    if(Get-ChildItem -LiteralPath $qaSource -Recurse -Force | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}){throw 'Refuse reparse points'}
    $qaFiles=@(Get-ChildItem -LiteralPath $qaSource -Recurse -File | ForEach-Object {@{path=[IO.Path]::GetRelativePath($qaSource,$_.FullName);sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower();bytes=$_.Length}})
    $qaRows+=@{source=$qaSource;destination=$qaDestination;files=$qaFiles}
}
foreach($qaRow in $qaRows){
    Move-Item -LiteralPath $qaRow.source -Destination $qaRow.destination
    foreach($qaFile in $qaRow.files){if((Get-FileHash -LiteralPath (Join-Path $qaRow.destination $qaFile.path) -Algorithm SHA256).Hash.ToLower() -ne $qaFile.sha256){throw 'Quarantine hash mismatch'}}
}
Copy-Item -LiteralPath (Join-Path $qaRoot 'reports/gameplay_qa/20260907_canopy_r18_build.log') -Destination (Join-Path $qaQuarantine 'build.log')
@{status='VISUAL_FAIL_RETAINED_NOT_DELETED';reason='R18 botanical silhouette is too spiky at actual phone game scale';source_generator_sha256=(Get-FileHash -LiteralPath (Join-Path $qaQuarantine 'source_generator.py') -Algorithm SHA256).Hash.ToLower();groups=$qaRows;disposal_authorized=$false} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $qaQuarantine 'retention_manifest.json') -Encoding utf8
Write-Output ('BOTANICAL_R18_RETAINED groups='+$qaRows.Count)
