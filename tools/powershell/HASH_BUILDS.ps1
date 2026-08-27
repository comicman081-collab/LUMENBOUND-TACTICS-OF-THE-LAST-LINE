. "$PSScriptRoot\COMMON.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Get-ProjectRoot
$builds = Join-Path $root 'builds'
New-Item -ItemType Directory -Path $builds -Force | Out-Null

# R7 uses stable canonical names and overwrites them in place. Do not allow
# stale review/deployment/log artifacts to enter the release checksum contract.
$canonicalBuildNames = @(
    'SD_STORY_RPG_HTML.zip',
    'SD_STORY_RPG_SOURCE.zip'
)

$files = foreach ($name in $canonicalBuildNames) {
    $path = Join-Path $builds $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Canonical R7 build is missing: $path"
    }
    Get-Item -LiteralPath $path
}

$lines = foreach ($file in $files) {
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($file.Name)"
}

$sumPath = Join-Path $builds 'SHA256SUMS.txt'
$temporarySumPath = Join-Path $builds ('SHA256SUMS_' + [Guid]::NewGuid().ToString('N') + '.tmp')
try {
    [System.IO.File]::WriteAllLines($temporarySumPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporarySumPath -Destination $sumPath -Force
} finally {
    if (Test-Path -LiteralPath $temporarySumPath) {
        Remove-Item -LiteralPath $temporarySumPath -Force
    }
}

Get-Content -LiteralPath $sumPath
