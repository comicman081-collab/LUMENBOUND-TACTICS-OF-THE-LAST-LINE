. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$builds = Join-Path $root 'builds'
New-Item -ItemType Directory -Path $builds -Force | Out-Null
$staging = Join-Path $builds ('source_staging_' + [Guid]::NewGuid().ToString('N'))
if (-not $staging.StartsWith($builds)) { throw 'Staging path escaped builds directory.' }
New-Item -ItemType Directory -Path $staging | Out-Null
foreach ($name in @('godot','data_source','tools','docs','tests','reports','README.md','WORKLOG.md','CHANGELOG.md','.gitignore')) {
    $source = Join-Path $root $name
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $staging -Recurse }
}
$cache = Join-Path $staging 'godot\.godot'
if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Recurse -Force }
$runtimeProfile = Join-Path $staging 'godot\.runtime_profile'
if (Test-Path -LiteralPath $runtimeProfile) { Remove-Item -LiteralPath $runtimeProfile -Recurse -Force }
$archivedLegacy = Join-Path $staging 'godot\assets\placeholders_legacy'
if (Test-Path -LiteralPath $archivedLegacy) { Remove-Item -LiteralPath $archivedLegacy -Recurse -Force }
$stagingResolved = (Resolve-Path $staging).Path
Get-ChildItem -LiteralPath $staging -Directory -Recurse -Filter '__pycache__' | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
    if (-not $_.FullName.StartsWith($stagingResolved)) { throw 'Refusing to remove cache outside staging.' }
    Remove-Item -LiteralPath $_.FullName -Recurse -Force
}
$zip = Join-Path $builds 'SD_STORY_RPG_SOURCE.zip'
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip -Force
if (-not (Resolve-Path $staging).Path.StartsWith((Resolve-Path $builds).Path)) { throw 'Refusing to remove staging outside builds.' }
Remove-Item -LiteralPath $staging -Recurse -Force
Write-Host "Source package: $zip"
