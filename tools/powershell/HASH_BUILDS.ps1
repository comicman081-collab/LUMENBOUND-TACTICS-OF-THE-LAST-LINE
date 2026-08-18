. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$builds = Join-Path $root 'builds'
New-Item -ItemType Directory -Path $builds -Force | Out-Null
$files = Get-ChildItem -LiteralPath $builds -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | Sort-Object Name
$lines = foreach ($file in $files) {
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($file.Name)"
}
$lines | Set-Content -LiteralPath (Join-Path $builds 'SHA256SUMS.txt') -Encoding utf8
Get-Content -LiteralPath (Join-Path $builds 'SHA256SUMS.txt')

