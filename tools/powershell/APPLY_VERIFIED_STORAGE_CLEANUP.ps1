$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$report = Join-Path $root 'reports/storage_cleanup_20260911'
$plan = Get-Content -LiteralPath (Join-Path $report 'retirement_plan.json') -Raw | ConvertFrom-Json
if ($plan.status -eq 'COMPLETE') { Write-Output 'This recorded cleanup has already completed.'; return }
if ($plan.status -ne 'HASHES_RECORDED_READY_FOR_DELETION' -or $plan.root -ne $root) { throw 'Retirement inventory is not ready.' }
$inventory = Join-Path $report 'retired_files.jsonl'
if ((Get-FileHash -LiteralPath $inventory -Algorithm SHA256).Hash -ne $plan.inventory_sha256) { throw 'Retirement inventory changed.' }
foreach ($suite in @('defeat_render','battle_loading')) {
    $checks = Get-Content -LiteralPath (Join-Path $report "$suite/acceptance.json") -Raw | ConvertFrom-Json
    if (@($checks.checks | Where-Object { -not $_.pass }).Count -gt 0) { throw "$suite did not pass." }
}
$player = Get-Content -LiteralPath (Join-Path $report 'player_verified/acceptance.json') -Raw | ConvertFrom-Json
if (-not $player.passed) { throw 'The retained player build did not pass.' }
if (-not (Select-String -LiteralPath (Join-Path $report 'headless.log') -Pattern 'TEST_SUMMARY total=301 pass=301 fail=0' -Quiet)) { throw 'Headless verification did not pass.' }
$version = Get-Content -LiteralPath (Join-Path $plan.keep_build 'VERSION.json') -Raw | ConvertFrom-Json
$pack = Join-Path $plan.keep_build ($version.runtime_artifact_base + '.pck')
if ((Get-FileHash -LiteralPath $pack -Algorithm SHA256).Hash -ne $plan.keep_pck_sha256) { throw 'The retained runtime changed.' }
$intro = (Get-Content -LiteralPath (Join-Path $report 'intro_preservation.json') -Raw | ConvertFrom-Json).protected_videos
$music = (Get-Content -LiteralPath (Join-Path $report 'music_preservation.json') -Raw | ConvertFrom-Json).files
foreach ($file in @($intro) + @($music)) {
    if ((Get-FileHash -LiteralPath (Join-Path $root $file.path) -Algorithm SHA256).Hash -ne $file.sha256) { throw "Protected media changed: $($file.path)" }
}
if (Get-Process -Name 'git','Godot*' -ErrorAction SilentlyContinue) { throw 'A Git or Godot writer is still running.' }
$result = [System.Collections.Generic.List[object]]::new()
$prefix = $root + [IO.Path]::DirectorySeparatorChar
foreach ($target in $plan.targets) {
    $path = [IO.Path]::GetFullPath($target.path)
    if (-not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Target escaped the project: $path" }
    if ($plan.keep_build -eq $path -or $plan.keep_build.StartsWith($path + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Retained build selected.' }
    foreach ($file in @($intro) + @($music)) {
        $protected = [IO.Path]::GetFullPath((Join-Path $root $file.path))
        if ($protected -eq $path -or $protected.StartsWith($path + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Protected media selected.' }
    }
    if (-not (Test-Path -LiteralPath $path)) { throw "A target disappeared after inventory: $path" }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse target: $path" }
    $children = if ($item.PSIsContainer) { @(Get-ChildItem -LiteralPath $path -Force -Recurse) } else { @($item) }
    if (@($children | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count) { throw "Reparse descendant: $path" }
    $files = @($children | Where-Object { -not $_.PSIsContainer })
    $bytes = ($files | Measure-Object -Property Length -Sum).Sum
    if ($files.Count -ne $target.files -or [long]$bytes -ne [long]$target.bytes) { throw "Target changed after inventory: $path" }
    # Both resolved boundaries and exact inventory totals are checked before
    # this single-shell, literal-path recursive removal.
    Remove-Item -LiteralPath $path -Recurse -Force
    if (Test-Path -LiteralPath $path) { throw "Removal incomplete: $path" }
    $result.Add(@{path=$path;bytes=$target.bytes;files=$target.files;reason=$target.reason;removed=$true})
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $report 'deleted_targets.json') -Encoding utf8
    Write-Output ("REMOVED {0:N3} GiB {1}" -f ($target.bytes/1GB),$target.relative)
}
Write-Output ("CLEANUP_COMPLETE {0:N3} GiB" -f (($result | Measure-Object -Property bytes -Sum).Sum/1GB))
