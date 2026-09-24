$ErrorActionPreference='Stop'
$qaRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$qaDestinationRoot=Join-Path $qaRoot 'work/gameplay_qa_quarantine_20260907/grounding_candidate32'
if(Test-Path -LiteralPath $qaDestinationRoot){throw 'Existing quarantine; preserve it'}
$qaRows=@()
foreach($qaPair in @(@{source='builds/web_gameplay_qa_20260907_candidate32';leaf='build'},@{source='reports/gameplay_qa/20260907_motion32_audit';leaf='motion_before'})){
    $qaSource=(Resolve-Path -LiteralPath (Join-Path $qaRoot $qaPair.source)).Path
    $qaDestination=[IO.Path]::GetFullPath((Join-Path $qaDestinationRoot $qaPair.leaf))
    foreach($qaPath in @($qaSource,$qaDestination)){if(-not $qaPath.StartsWith($qaRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Outside project'}}
    if((Get-Item -LiteralPath $qaSource).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Refuse reparse source'}
    $qaItems=@(Get-ChildItem -LiteralPath $qaSource -Recurse -Force)
    if($qaItems | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}){throw 'Refuse reparse child'}
    $qaFiles=@($qaItems | Where-Object {-not $_.PSIsContainer} | ForEach-Object {@{path=[IO.Path]::GetRelativePath($qaSource,$_.FullName);sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower();bytes=$_.Length}})
    $qaRows+=@{source=$qaSource;destination=$qaDestination;files=$qaFiles}
}
New-Item -ItemType Directory -Path $qaDestinationRoot | Out-Null
foreach($qaRow in $qaRows){Move-Item -LiteralPath $qaRow.source -Destination $qaRow.destination;foreach($qaFile in $qaRow.files){if((Get-FileHash -LiteralPath (Join-Path $qaRow.destination $qaFile.path) -Algorithm SHA256).Hash.ToLower() -ne $qaFile.sha256){throw 'Hash mismatch'}}}
@{status='VISUAL_FAIL_RETAINED';reason='Five allies crowd the narrow original cathedral floor despite numeric contact pass';disposal_authorized=$false;groups=$qaRows} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $qaDestinationRoot 'retention_manifest.json') -Encoding utf8
Write-Output ('RETAINED_WITHOUT_DELETION groups='+$qaRows.Count)
