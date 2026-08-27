. "$PSScriptRoot\COMMON.ps1"

$root = Get-ProjectRoot
$godot = Find-Godot471
$python = Find-LocalPython
Set-ProjectGodotUserPaths $root
Copy-GodotWindowsTemplatesToProjectProfile $root

$audioBuilder = Join-Path $root 'tools\audio\build_audio_pack.py'
$dataGenerator = Join-Path $root 'tools\generate_data.py'
$runtimeBuilder = Join-Path $root 'tools\web\build_runtime_combat_packs.py'
foreach ($requiredTool in @($audioBuilder, $dataGenerator, $runtimeBuilder)) {
	if (-not (Test-Path -LiteralPath $requiredTool -PathType Leaf)) { throw "Build tool missing: $requiredTool" }
}

Invoke-Checked $python @($audioBuilder)
Invoke-Checked $python @($dataGenerator)
Invoke-Checked $python @($runtimeBuilder)

$buildRoot = [IO.Path]::GetFullPath((Join-Path $root 'builds'))
$output = [IO.Path]::GetFullPath((Join-Path $buildRoot 'windows_development'))
$expected = [IO.Path]::GetFullPath((Join-Path $root 'builds\windows_development'))
if (-not $output.Equals($expected, [StringComparison]::OrdinalIgnoreCase) -or
	-not $output.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) {
	throw "Refusing to replace an unexpected Windows output: $output"
}
if (Test-Path -LiteralPath $output -PathType Container) {
	Remove-Item -LiteralPath $output -Recurse -Force
}
New-Item -ItemType Directory -Path $output -Force | Out-Null

# Reuse the validated Web Development resource filter and feature flag to make
# a platform-independent PCK, then pair it with Godot's official Windows 4.7.1
# release template. Godot loads a same-basename PCK beside the executable.
$baseName = 'LANTERNLINE_DEV'
$pck = Join-Path $output "$baseName.pck"
$exe = Join-Path $output "$baseName.exe"
Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), '--export-pack', 'Web Development', $pck)

$template = Join-Path $env:APPDATA 'Godot\export_templates\4.7.1.stable\windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw "Windows template missing after copy: $template" }
Copy-Item -LiteralPath $template -Destination $exe -Force

foreach ($artifact in @($exe, $pck)) {
	if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) { throw "Windows artifact missing: $artifact" }
	if ((Get-Item -LiteralPath $artifact).Length -le 0) { throw "Windows artifact is empty: $artifact" }
}

$version = [ordered]@{
	build_id = 'LANTERNLINE_WINDOWS_DEVELOPMENT'
	engine = 'Godot 4.7.1-stable'
	target = 'Windows x86_64 portable'
	production_approved = $false
	executable_sha256 = Get-FileSha256 $exe
	pck_sha256 = Get-FileSha256 $pck
	created_utc = [DateTime]::UtcNow.ToString('o')
}
$version | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'VERSION.json') -Encoding UTF8

@'
# LANTERNLINE Windows Development

Run `LANTERNLINE_DEV.exe`. Keep `LANTERNLINE_DEV.pck` in the same folder.
This is a local QA build and has not been approved or deployed as a public release.
'@ | Set-Content -LiteralPath (Join-Path $output 'README.md') -Encoding UTF8

Write-Host "WINDOWS_DEVELOPMENT_EXE=$exe"
Write-Host "WINDOWS_DEVELOPMENT_PCK=$pck"
