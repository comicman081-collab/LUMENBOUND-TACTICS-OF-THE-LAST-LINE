Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:OriginalAppData = $env:APPDATA

function Get-ProjectRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Find-Godot471 {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:GODOT_471_PATH) { $candidates.Add($env:GODOT_471_PATH) }
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) { $candidates.Add($command.Source) }
    foreach ($path in @(
        (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.1-stable_win64_console.exe'),
        (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.1-stable_win64.exe'),
        (Join-Path $env:USERPROFILE 'Desktop\Godot_v4.7.1-stable_win64_console.exe'),
        (Join-Path $env:USERPROFILE 'Desktop\Godot_v4.7.1-stable_win64.exe'),
        'D:\AI 종합 폴더\Godot\4.7.1-standard\Godot_v4.7.1-stable_win64_console.exe',
        'D:\AI 종합 폴더\Godot\4.7.1-standard\Godot_v4.7.1-stable_win64.exe',
        'C:\Godot\Godot_v4.7.1-stable_win64_console.exe',
        'C:\Godot\Godot_v4.7.1-stable_win64.exe'
    )) { $candidates.Add($path) }
    Write-Host 'Godot 탐색 후보:'
    $candidates | Select-Object -Unique | ForEach-Object { Write-Host " - $_" }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $version = (& $candidate --version 2>$null | Select-Object -First 1).Trim()
        Write-Host "발견: $candidate ($version)"
        if ($version -notmatch '^4\.7\.1\.stable') {
            throw "Godot 4.7.1 Stable이 아닙니다: $version"
        }
        return (Resolve-Path -LiteralPath $candidate).Path
    }
    throw 'Godot 4.7.1 Stable Standard 실행 파일을 찾지 못했습니다. GODOT_471_PATH를 설정하십시오.'
}

function Find-LocalPython {
    $command = Get-Command python -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidate = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    throw '로컬 Python을 찾지 못했습니다. 빌드 도구용 Python만 필요하며 게임 런타임에는 필요하지 않습니다.'
}

function Find-Blender45 {
    $candidates = @(
        $env:BLENDER_PATH,
        'C:\Program Files\Blender Foundation\Blender 4.5\blender.exe'
    ) | Where-Object { $_ }
    Write-Host 'Blender 탐색 후보:'
    $candidates | ForEach-Object { Write-Host " - $_" }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $version = (& $candidate --background --version 2>$null | Select-Object -First 1).Trim()
        Write-Host "발견: $candidate ($version)"
        if ($version -notmatch '^Blender 4\.5\.') { throw "검증된 Blender 4.5 LTS가 아닙니다: $version" }
        return (Resolve-Path -LiteralPath $candidate).Path
    }
    throw 'Blender 4.5 LTS 실행 파일을 찾지 못했습니다. BLENDER_PATH를 설정하십시오.'
}

function Find-Blender45 {
    $candidates = @(
        $env:BLENDER_PATH,
        'C:\Program Files\Blender Foundation\Blender 4.5\blender.exe'
    ) | Where-Object { $_ }
    Write-Host 'Blender 탐색 후보:'
    $candidates | ForEach-Object { Write-Host " - $_" }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $version = (& $candidate --background --version 2>$null | Select-Object -First 1).Trim()
        Write-Host "발견: $candidate ($version)"
        if ($version -notmatch '^Blender 4\.5\.') { throw "검증된 Blender 4.5 LTS가 아닙니다: $version" }
        return (Resolve-Path -LiteralPath $candidate).Path
    }
    throw 'Blender 4.5 LTS 실행 파일을 찾지 못했습니다. BLENDER_PATH를 설정하십시오.'
}

function Invoke-Checked([string]$Executable, [string[]]$Arguments) {
    $lines = @(& $Executable @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $lines | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) { throw "$Executable 종료 코드: $exitCode" }
    $fatalOutput = $lines | Where-Object { "$_" -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script|Traceback \(most recent call last\):|ModuleNotFoundError:' }
    if ($fatalOutput) {
        throw "$Executable 가 종료 코드 0과 함께 스크립트 오류를 출력했습니다. 오류 출력을 실패로 처리합니다."
    }
}

function Set-ProjectGodotUserPaths([string]$Root) {
	# Every invocation receives an isolated writable profile. This prevents a
	# crashed/headless child from retaining Godot's AppData log lock and also
	# keeps the user's global AppData untouched.
	$stamp = '{0}-{1}' -f $PID, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
	$qa = Join-Path $Root (Join-Path 'godot\.runtime_profile\runs' $stamp)
    $roaming = Join-Path $qa 'Roaming'
    $local = Join-Path $qa 'Local'
    New-Item -ItemType Directory -Force -Path $roaming, $local | Out-Null
    $env:APPDATA = $roaming
    $env:LOCALAPPDATA = $local
    Write-Host "Godot QA 사용자 데이터: $qa"
}

function Copy-GodotWebTemplatesToProjectProfile([string]$Root) {
	$source = Join-Path $script:OriginalAppData 'Godot\export_templates\4.7.1.stable'
	$destination = Join-Path $env:APPDATA 'Godot\export_templates\4.7.1.stable'
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Godot 4.7.1 Web export template source missing: $source"
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    foreach ($name in @('web_nothreads_debug.zip', 'web_nothreads_release.zip')) {
        $from = Join-Path $source $name
        $to = Join-Path $destination $name
        if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { throw "Web export template missing: $from" }
        if (-not (Test-Path -LiteralPath $to -PathType Leaf) -or (Get-Item -LiteralPath $to).Length -ne (Get-Item -LiteralPath $from).Length) {
            Copy-Item -LiteralPath $from -Destination $to -Force
        }
    }
}
