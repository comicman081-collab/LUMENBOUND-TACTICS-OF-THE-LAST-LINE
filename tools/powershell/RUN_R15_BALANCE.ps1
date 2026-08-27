param(
    [ValidateRange(1, 1000)]
    [int]$RunsPerCell = 200,
    [ValidateRange(0, 90)]
    [int]$MaxCells = 0,
    [ValidateRange(0, 89)]
    [int]$StartCell = 0,
    [switch]$Resume,
    [ValidatePattern('^[A-Za-z0-9_.-]+\.json$')]
    [string]$OutputName = 'R15_CH01_BALANCE_MATRIX.json'
)

. "$PSScriptRoot\COMMON.ps1"

$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
$resumeArg = if ($Resume) { '1' } else { '0' }
Write-Host "R15 balance: runs/cell=$RunsPerCell maxCells=$MaxCells startCell=$StartCell resume=$($Resume.IsPresent) output=$OutputName"
$godotArgs = @(
    '--headless',
    '--path', (Join-Path $root 'godot'),
    'res://tools/r15_balance_matrix.tscn',
    '--',
    "$RunsPerCell",
    $OutputName,
    "$MaxCells",
    $resumeArg,
    "$StartCell"
)
$lines = [System.Collections.Generic.List[string]]::new()
& $godot @godotArgs 2>&1 | ForEach-Object {
    $line = "$_"
    $lines.Add($line)
    # The matrix checkpoints every completed cell.  Stream that proof rather
    # than buffering a multi-minute run until process exit.
    Write-Host $line
}
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) { throw "$godot 종료 코드: $exitCode" }
$fatalOutput = $lines | Where-Object { "$_" -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script|Traceback \(most recent call last\):|ModuleNotFoundError:' }
if ($fatalOutput) {
    throw "$godot 가 종료 코드 0과 함께 스크립트 오류를 출력했습니다. 오류 출력을 실패로 처리합니다."
}
