param(
    [switch]$Serve,
    [int]$Port = 8081
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$release = Join-Path $root 'builds\web_r7_current_release'
$builds = Join-Path $root 'builds'
$zip = Join-Path $builds 'SD_STORY_RPG_R7_INITIAL_WEB.zip'

if (-not (Test-Path -LiteralPath $release -PathType Container)) { throw "R7 release directory missing: $release" }
$required = @('index.html','index.js','index.manifest.json','index.service.worker.js','index.offline.html','VERSION.json','LICENSES.md')
foreach ($name in $required) {
    $path = Join-Path $release $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required Web deployment file missing: $path" }
}
$runtime = @(Get-ChildItem -LiteralPath $release -File | Where-Object { $_.Extension -in @('.pck','.wasm') })
if ($runtime.Count -ne 2) { throw "Expected exactly one PCK and one WASM in R7 release; found $($runtime.Count)." }

if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in Get-ChildItem -LiteralPath $release -File) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $file.Name, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose() }

$version = Get-Content -LiteralPath (Join-Path $release 'VERSION.json') -Raw | ConvertFrom-Json
$zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
$zipBytes = (Get-Item -LiteralPath $zip).Length
Write-Host "WEB_R7_INITIAL_ZIP=$zip"
Write-Host "WEB_R7_INITIAL_BYTES=$zipBytes"
Write-Host "WEB_R7_INITIAL_SHA256=$zipHash"
Write-Host "WEB_R7_RELEASE=$release"
Write-Host "WEB_R7_BUILD_ID=$($version.build_id)"
if ($Serve) {
    if ($Port -ne 8081) { throw 'R7 deployment port is fixed at 8081.' }
    $python = 'C:\Users\AAA\AppData\Local\Programs\Python\Python311\python.exe'
    if (-not (Test-Path -LiteralPath $python)) { $python = (Get-Command python.exe -ErrorAction Stop).Source }
    Write-Host "WEB_R7_URL=http://127.0.0.1:8081/index.html?build=r7_current"
    & $python -m http.server 8081 --bind 127.0.0.1 --directory $release
}
