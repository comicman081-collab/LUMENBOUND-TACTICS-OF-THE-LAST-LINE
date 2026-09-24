$ErrorActionPreference='Stop'
$qaRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$qaDestinationRoot=Join-Path $qaRoot 'work/gameplay_qa_quarantine_20260907/grounding_predecessors'
if(Test-Path -LiteralPath $qaDestinationRoot){throw 'Existing quarantine; do not overwrite'}
$qaTargets=@(
    @{source='builds/web_gameplay_qa_20260907_candidate31';leaf='candidate31';reason='Visual FAIL: action-dependent body scale and floor mismatch'},
    @{source='reports/gameplay_qa/20260907_motion31_audit';leaf='motion31_before';reason='Real recording retained as evidence of the reported grounding failure'},
    @{source='reports/gameplay_qa/20260907_motion31_visual_r2';leaf='motion31_visual_before';reason='Actual frame sequences retained as before evidence'},
    @{source='reports/gameplay_qa/20260907_motion31_visual';leaf='motion31_bad_duration';reason='QA extraction FAIL: unknown WebM frame count produced negative duration'},
    @{source='work/reference_cache/combat_motion_20260907/analysis_manifest.json';leaf='reference_bad_unicode_manifest.json';reason='QA extraction FAIL: Unicode imwrite did not create claimed images'}
)
$qaRows=@()
foreach($qaTarget in $qaTargets){
    $qaSource=(Resolve-Path -LiteralPath (Join-Path $qaRoot $qaTarget.source)).Path
    $qaDestination=[IO.Path]::GetFullPath((Join-Path $qaDestinationRoot $qaTarget.leaf))
    foreach($qaPath in @($qaSource,$qaDestination)){
        if(-not $qaPath.StartsWith($qaRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Outside project'}
    }
    $qaSourceItem=Get-Item -LiteralPath $qaSource
    if($qaSourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Refuse reparse source'}
    $qaItems=if($qaSourceItem.PSIsContainer){@(Get-ChildItem -LiteralPath $qaSource -Recurse -Force)}else{@($qaSourceItem)}
    if($qaItems | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}){throw 'Refuse reparse child'}
    $qaFiles=@($qaItems | Where-Object {-not $_.PSIsContainer} | ForEach-Object {@{path=if($qaSourceItem.PSIsContainer){[IO.Path]::GetRelativePath($qaSource,$_.FullName)}else{''};sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower();bytes=$_.Length}})
    $qaRows+=@{source=$qaSource;destination=$qaDestination;reason=$qaTarget.reason;files=$qaFiles}
}
New-Item -ItemType Directory -Path $qaDestinationRoot | Out-Null
foreach($qaRow in $qaRows){
    Move-Item -LiteralPath $qaRow.source -Destination $qaRow.destination
    foreach($qaFile in $qaRow.files){
        $qaFilePath=if($qaFile.path){Join-Path $qaRow.destination $qaFile.path}else{$qaRow.destination}
        if((Get-FileHash -LiteralPath $qaFilePath -Algorithm SHA256).Hash.ToLower() -ne $qaFile.sha256){throw 'Quarantine hash mismatch'}
    }
}
@{status='FAILED_VISUAL_AND_QA_EVIDENCE_RETAINED';disposal_authorized=$false;groups=$qaRows} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $qaDestinationRoot 'retention_manifest.json') -Encoding utf8
Write-Output ('RETAINED_WITHOUT_DELETION groups='+$qaRows.Count)
