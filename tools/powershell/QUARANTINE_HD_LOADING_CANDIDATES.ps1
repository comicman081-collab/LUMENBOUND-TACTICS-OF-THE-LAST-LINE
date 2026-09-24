Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$outputRoot=[IO.Path]::GetFullPath((Join-Path $taskRoot 'work/gameplay_qa_quarantine_20260907/hd_loading_candidates'))
if(Test-Path -LiteralPath $outputRoot){throw 'Immutable quarantine exists.'}
$reasons=@{21='Rejected shader light-count experiment; no material startup improvement.';22='Valid HD actor canvas rejected by JSON float/integer array comparison; incomplete signature metadata.';23='HD actor JSON dimension rejection; never accepted as all-HD.';24='Verified page loading was not reported to idle watchdog; N20 entry aborted.'}
$records=@()
foreach($number in @(21,22,23,24)){
    $source=(Resolve-Path -LiteralPath (Join-Path $taskRoot "builds/web_gameplay_qa_20260907_candidate$number")).Path
    $destination=[IO.Path]::GetFullPath((Join-Path $outputRoot "candidate$number"))
    if(-not $source.StartsWith((Join-Path $taskRoot 'builds')+[IO.Path]::DirectorySeparatorChar) -or -not $destination.StartsWith($outputRoot+[IO.Path]::DirectorySeparatorChar)){throw 'Unsafe quarantine path.'}
    $files=@(Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object {@{relative=[IO.Path]::GetRelativePath($source,$_.FullName);bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
    $records+=@{source=$source;destination=$destination;reason=$reasons[$number];files=$files}
}
New-Item -ItemType Directory -Path $outputRoot | Out-Null
@{status='RETAIN_NO_DISPOSAL';deleted=0;records=$records}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $outputRoot 'retention_manifest.json') -Encoding utf8
foreach($record in $records){
    Move-Item -LiteralPath $record.source -Destination $record.destination
    foreach($file in $record.files){if((Get-FileHash -LiteralPath (Join-Path $record.destination $file.relative) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256){throw 'Retained file hash mismatch.'}}
}
Write-Output 'HD_LOADING_FAILED_BUILDS_QUARANTINED groups=4 deleted=0'
