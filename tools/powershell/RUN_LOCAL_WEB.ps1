param(
    [string]$BuildDirectory = 'builds\web_development',
    [ValidateRange(1024, 65535)]
    [int]$Port = 8767
)
. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$python = Find-LocalPython
$directory = [IO.Path]::GetFullPath((Join-Path $root $BuildDirectory))
$buildRoot = [IO.Path]::GetFullPath((Join-Path $root 'builds')).TrimEnd('\') + '\'
if (-not $directory.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase) -or
    -not (Test-Path -LiteralPath (Join-Path $directory 'index.html') -PathType Leaf)) {
    throw 'Select an existing Web export beneath this project builds directory.'
}
Invoke-Checked $python @((Join-Path $root 'tools\web\stage_density_sidecars.py'), $directory, '--validate-only')
Invoke-Checked $python @((Join-Path $root 'tools\web\stage_audio_sidecars.py'), $directory, '--validate-only')
Write-Host "Local game: http://127.0.0.1:$Port/"
Write-Host 'Keep this terminal open while playing. Press Ctrl+C to stop.'
& $python -u -m http.server $Port --bind 127.0.0.1 --directory $directory
if ($LASTEXITCODE -ne 0) { throw "Local Web server stopped with exit code $LASTEXITCODE" }
