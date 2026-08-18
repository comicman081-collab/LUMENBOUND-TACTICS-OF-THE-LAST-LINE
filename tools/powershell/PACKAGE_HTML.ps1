. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$source = Join-Path $root 'builds\web_release'
$target = Join-Path $root 'builds\SD_STORY_RPG_HTML.zip'
if (-not (Test-Path -LiteralPath (Join-Path $source 'index.html') -PathType Leaf)) { throw "Web release missing: $source" }
Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $source -Force).FullName -DestinationPath $target -Force
Write-Host "HTML package: $target"
