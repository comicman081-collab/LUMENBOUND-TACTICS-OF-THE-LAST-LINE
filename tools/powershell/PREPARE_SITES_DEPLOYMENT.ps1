$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$release = Join-Path $root 'builds\web_r7_current_release'
$dist = Join-Path $root 'dist'
$client = Join-Path $dist 'client'
$server = Join-Path $dist 'server'

if (-not (Test-Path -LiteralPath (Join-Path $release 'index.html') -PathType Leaf)) {
    throw "R7 Web Release is missing: $release"
}
if (Test-Path -LiteralPath $client) { Remove-Item -LiteralPath $client -Recurse -Force }
New-Item -ItemType Directory -Path $client,$server -Force | Out-Null
Get-ChildItem -LiteralPath $release -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $client -Recurse -Force
}
Write-Host "SITES_CLIENT=$client"
Write-Host "SITES_SERVER=$server"
