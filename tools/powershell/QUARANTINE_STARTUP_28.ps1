$ErrorActionPreference='Stop'
$qaRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$qaSource=(Resolve-Path -LiteralPath (Join-Path $qaRoot 'builds/web_gameplay_qa_20260907_candidate28')).Path
$qaDestination=[IO.Path]::GetFullPath((Join-Path $qaRoot 'work/gameplay_qa_quarantine_20260907/startup_candidate28'))
foreach($qaPath in @($qaSource,$qaDestination)) {
    if(-not $qaPath.StartsWith($qaRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Outside project'}
}
if(Test-Path -LiteralPath $qaDestination){throw 'Quarantine destination already exists'}
if(Get-ChildItem -LiteralPath $qaSource -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }){throw 'Refuse reparse points'}
$qaRows=@(Get-ChildItem -LiteralPath $qaSource -File -Recurse | ForEach-Object {
    @{path=[IO.Path]::GetRelativePath($qaSource,$_.FullName);sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower();bytes=$_.Length}
})
Move-Item -LiteralPath $qaSource -Destination $qaDestination
foreach($qaRow in $qaRows){
    if((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $qaDestination $qaRow.path)).Hash.ToLower() -ne $qaRow.sha256){throw 'Quarantine hash mismatch'}
}
$qaManifest=@{status='FAIL_RETAINED_NOT_DELETED';reason='Matte specular-disabled per-pixel experiment did not reduce cold shader startup (24.508 seconds); candidate29 vertex-lighting replacement measured 7.951 seconds, further gates ongoing';source=$qaSource;destination=$qaDestination;files=$qaRows;disposal_authorized=$false}
$qaManifest | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $qaDestination 'retention_manifest.json') -Encoding utf8
Write-Output ('RETAINED_NO_DELETION files='+$qaRows.Count)
