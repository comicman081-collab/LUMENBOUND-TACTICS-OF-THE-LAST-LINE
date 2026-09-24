param([ValidateSet('enemy_replacement_20260911','existing_roster_spritegen_20260911')][string]$RunName='enemy_replacement_20260911')
$ErrorActionPreference = 'Stop'
$count = if ($RunName -eq 'enemy_replacement_20260911') {52} else {21}
$retirementName = if ($count -eq 52) {'enemy_placeholders_20260911'} else {'existing_roster_pre_spritegen_20260911'}
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$prefix = $root.TrimEnd('\') + '\'
function Confirm-ProjectPath([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    if (-not $absolute.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Outside project: $absolute" }
    return $absolute
}
$reportRoot = Confirm-ProjectPath (Join-Path $root ('reports/' + $RunName))
$proof = Get-Content -LiteralPath (Join-Path $reportRoot 'staged_runtime_verification.json') -Raw | ConvertFrom-Json
if ($proof.status -ne 'PASS' -or $proof.entities -ne $count) { throw 'Entire staged batch must pass before installation' }
$staged = Confirm-ProjectPath (Join-Path $root ('work/' + $RunName + '/staged'))
$runtime = Confirm-ProjectPath (Join-Path $root 'godot/assets/runtime_web')
$retained = Confirm-ProjectPath (Join-Path $root ('quarantine/' + $retirementName))
if (Test-Path -LiteralPath $retained) { throw 'Immutable retirement folder already exists' }
$summary = Get-Content -LiteralPath (Join-Path $staged 'build_summary.json') -Raw | ConvertFrom-Json
$ids = @($summary.actors.PSObject.Properties.Name | Sort-Object)
if ($ids.Count -ne $count) { throw 'Incomplete staged actor set' }
$families = @(@{stage='combat';runtime='combat'},@{stage='full_density';runtime='full_density/r2'},@{stage='map_density';runtime='map_density/r1'})
$operations = @()
$inventory = @()
foreach ($family in $families) {
    foreach ($id in $ids) {
        if ($id -notmatch '^(CHR|ENM|BOSS)\d{3}$') { throw 'Invalid actor ID' }
        $old = Confirm-ProjectPath (Join-Path $runtime ($family.runtime + '/' + $id))
        $new = Confirm-ProjectPath (Join-Path $staged ($family.stage + '/' + $id))
        $backup = Confirm-ProjectPath (Join-Path $retained ($family.runtime + '/' + $id))
        if (-not (Test-Path -LiteralPath $old -PathType Container) -or -not (Test-Path -LiteralPath $new -PathType Container)) { throw "Missing pack: $id" }
        if ((Get-Item -LiteralPath $old).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse source refused' }
        foreach ($file in Get-ChildItem -LiteralPath $old -File -Recurse) {
            $inventory += @{path=$file.FullName.Substring($root.Length+1);sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant();bytes=$file.Length}
        }
        $operations += @{old=$old;new=$new;backup=$backup}
    }
}
New-Item -ItemType Directory -Path $retained | Out-Null
@{status='RETAINED_PLACEHOLDERS_PENDING_FINAL_RUNTIME_GATES';assets=$inventory} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $retained 'retirement_manifest.json') -Encoding utf8
foreach ($operation in $operations) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $operation.backup) | Out-Null
    Move-Item -LiteralPath $operation.old -Destination $operation.backup
    Copy-Item -LiteralPath $operation.new -Destination $operation.old -Recurse
}
foreach ($family in $families | Where-Object { $_.stage -ne 'combat' }) {
    $indexPath = Confirm-ProjectPath (Join-Path $runtime ($family.runtime + '/index.json'))
    $backup = Confirm-ProjectPath (Join-Path $retained ($family.runtime + '/index.json'))
    Copy-Item -LiteralPath $indexPath -Destination $backup
    $index = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
    $replacement = Get-Content -LiteralPath (Join-Path $staged ($family.stage + '/index.json')) -Raw | ConvertFrom-Json
    foreach ($id in $ids) { $index.actors | Add-Member -NotePropertyName $id -NotePropertyValue $replacement.actors.$id -Force }
    [IO.File]::WriteAllText($indexPath,($index | ConvertTo-Json -Depth 100),(New-Object Text.UTF8Encoding($false)))
}
Write-Host "REVIEWED_ACTORS_INSTALLED $count actors; previous local player build unchanged"
